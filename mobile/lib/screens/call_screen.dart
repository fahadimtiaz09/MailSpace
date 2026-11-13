// call_screen.dart — voice / video call (same system as the website).
//
// Making a call  (CallScreen.outgoing):
//   camera/mic on → WebRTC "offer" → POST /api/calls → "Ringing…"
//   → the other side answers (we check GET /api/calls/<id>) → connected
// Getting a call (CallScreen.incoming, opened by CallService):
//   Accept → camera/mic on → WebRTC "answer" → POST /api/calls/<id>/answer
// Hanging up → POST /api/calls/<id>/end → the server emails both people
// the start time and how long the call lasted.
//
// Voice and video go straight between the two phones/browsers (WebRTC);
// our server only passes the connection details.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../api/api_client.dart';
import '../services/call_service.dart';
import '../widgets/brand.dart';
import '../widgets/message_row.dart';

class CallScreen extends StatefulWidget {
  final String other;   // the other person's email
  final String kind;    // 'audio' or 'video'
  final bool isIncoming;
  final String? callId;
  final Map<String, dynamic>? offer;

  const CallScreen.outgoing({super.key, required this.other, required this.kind})
      : isIncoming = false,
        callId = null,
        offer = null;

  CallScreen.incoming(Map<String, dynamic> call, {super.key})
      : other = call['other'] as String? ?? '',
        kind = call['kind'] as String? ?? 'audio',
        isIncoming = true,
        callId = call['id'] as String?,
        offer = call['offer'] is Map ? Map<String, dynamic>.from(call['offer'] as Map) : null;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  static const _iceServers = {
    'iceServers': [
      {'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302']},
    ],
    'sdpSemantics': 'unified-plan',
  };

  final _api = ApiClient.instance;
  final _localView = RTCVideoRenderer();
  final _remoteView = RTCVideoRenderer();
  late final Future<void> _viewsReady = _initViews();

  RTCPeerConnection? _pc;
  MediaStream? _local;
  Completer<void>? _iceDone;

  String? _id;
  String _status = '';
  bool _ringingForMe = false;   // incoming call not answered yet
  bool _inCall = false;         // answered — show mute / camera / end
  bool _connected = false;
  bool _hasRemoteVideo = false;
  bool _muted = false;
  bool _cameraOff = false;
  late bool _speaker = widget.kind == 'video';
  DateTime? _startedAt;
  Timer? _poll;
  Timer? _tick;
  Timer? _buzz;
  bool _closing = false;

  bool get _isVideo => widget.kind == 'video';

  @override
  void initState() {
    super.initState();
    CallService.instance.inCall = true;
    if (widget.isIncoming) {
      _id = widget.callId;
      _ringingForMe = true;
      _status = _isVideo ? 'Incoming video call…' : 'Incoming voice call…';
      // Vibrate like a phone call (no ringtone file needed)
      _buzz = Timer.periodic(const Duration(milliseconds: 1400), (_) => HapticFeedback.heavyImpact());
      _startPolling();
    } else {
      _status = 'Starting…';
      _startOutgoing();
    }
  }

  Future<void> _initViews() async {
    await _localView.initialize();
    await _remoteView.initialize();
  }

  // ---------------- helpers ----------------

  Future<MediaStream> _openMedia() async {
    try {
      return await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': _isVideo ? {'facingMode': 'user'} : false,
      });
    } catch (_) {
      throw ApiException(_isVideo
          ? 'Allow camera and microphone access to make video calls.'
          : 'Allow microphone access to make calls.');
    }
  }

  Future<RTCPeerConnection> _makePeer() async {
    final pc = await createPeerConnection(_iceServers);
    _iceDone = Completer<void>();
    pc.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete && !(_iceDone?.isCompleted ?? true)) {
        _iceDone!.complete();
      }
    };
    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isEmpty) return;
      _remoteView.srcObject = event.streams[0];
      if (event.track.kind == 'video' && mounted) setState(() => _hasRemoteVideo = true);
    };
    pc.onConnectionState = (state) {
      if (!mounted) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() => _connected = true);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _hangUp(message: 'The connection was lost.');
      }
    };
    return pc;
  }

  /// Wait (max 3 s) until the phone has found its network addresses,
  /// so the whole offer/answer is sent in one go.
  Future<Map<String, String>> _finishedDescription(RTCPeerConnection pc) async {
    await (_iceDone?.future ?? Future.value()).timeout(const Duration(seconds: 3), onTimeout: () {});
    final d = await pc.getLocalDescription();
    return {'type': d?.type ?? '', 'sdp': d?.sdp ?? ''};
  }

  Future<void> _addLocalMedia(RTCPeerConnection pc) async {
    final local = await _openMedia();
    _local = local;
    await _viewsReady;
    _localView.srcObject = local;
    for (final track in local.getTracks()) {
      await pc.addTrack(track, local);
    }
    _applySpeaker();
    if (mounted) setState(() {});
  }

  void _applySpeaker() {
    if (kIsWeb) return;
    try {
      Helper.setSpeakerphoneOn(_speaker);
    } catch (_) {}
  }

  // ---------------- making a call ----------------

  Future<void> _startOutgoing() async {
    try {
      await _viewsReady;
      final pc = await _makePeer();
      _pc = pc;
      await _addLocalMedia(pc);
      await pc.setLocalDescription(await pc.createOffer());
      final offer = await _finishedDescription(pc);
      if (_closing) return;
      final call = await _api.startCall(widget.other, widget.kind, offer);
      _id = call['id'] as String;
      CallService.instance.activeCallId = _id;
      if (_closing) {
        _api.endCall(_id!);
        return;
      }
      setState(() => _status = 'Ringing…');
      _startPolling();
    } on ApiException catch (e) {
      _close(e.message);
    } catch (_) {
      _close('Could not start the call.');
    }
  }

  // ---------------- answering ----------------

  Future<void> _accept() async {
    _buzz?.cancel();
    if (_id != null) CallService.instance.markHandled(_id!);
    setState(() {
      _ringingForMe = false;
      _status = 'Connecting…';
    });
    try {
      await _viewsReady;
      final pc = await _makePeer();
      _pc = pc;
      final offer = widget.offer ?? {};
      await pc.setRemoteDescription(RTCSessionDescription(offer['sdp'] as String?, offer['type'] as String?));
      await _addLocalMedia(pc);
      await pc.setLocalDescription(await pc.createAnswer());
      final answer = await _finishedDescription(pc);
      if (_closing) return;
      final call = await _api.answerCall(_id!, answer);
      CallService.instance.activeCallId = _id;
      _startTimer(call['started_at'] as String?);
      setState(() => _inCall = true);
    } on ApiException catch (e) {
      _hangUp(message: e.message);
    } catch (_) {
      _hangUp(message: 'Could not answer the call.');
    }
  }

  // ---------------- watching the call ----------------

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 1200), (_) => _check());
  }

  bool _checking = false;
  Future<void> _check() async {
    if (_id == null || _checking || _closing) return;
    _checking = true;
    try {
      final call = await _api.getCall(_id!);
      final status = call['status'] as String?;
      if (status == 'active') {
        final answer = call['answer'];
        if (!widget.isIncoming && answer is Map && _pc != null && !_inCall) {
          await _pc!.setRemoteDescription(RTCSessionDescription(answer['sdp'] as String?, answer['type'] as String?));
          if (mounted) setState(() => _inCall = true);
        }
        _startTimer(call['started_at'] as String?);
      } else if (status != 'ringing') {
        final name = widget.other.split('@').first;
        final text = switch (status) {
          'declined' => '$name declined the call.',
          'missed' => widget.isIncoming ? 'Missed call from $name.' : 'No answer.',
          _ => 'Call ended · ${_formatTimer((call['duration'] as num?)?.toInt() ?? 0)}',
        };
        _close(text);
      }
    } on ApiException catch (e) {
      if (e.statusCode == 404) _close('Call ended.');
    } catch (_) {
      // network hiccup — try again
    } finally {
      _checking = false;
    }
  }

  void _startTimer(String? startedIso) {
    if (_tick != null) return;
    var started = DateTime.tryParse(startedIso ?? '')?.toLocal() ?? DateTime.now();
    if (DateTime.now().difference(started).abs() > const Duration(seconds: 15)) started = DateTime.now();
    _startedAt = started;
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  static String _formatTimer(int seconds) {
    final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  String get _statusText {
    if (_inCall && _startedAt != null) {
      if (!_connected) return 'Connecting…';
      return _formatTimer(DateTime.now().difference(_startedAt!).inSeconds);
    }
    return _status;
  }

  // ---------------- buttons ----------------

  void _toggleMute() {
    setState(() => _muted = !_muted);
    for (final t in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !_muted;
    }
  }

  void _toggleCamera() {
    setState(() => _cameraOff = !_cameraOff);
    for (final t in _local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !_cameraOff;
    }
  }

  Future<void> _switchCamera() async {
    final tracks = _local?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (_) {}
  }

  void _toggleSpeaker() {
    setState(() => _speaker = !_speaker);
    _applySpeaker();
  }

  // ---------------- ending ----------------

  Future<void> _hangUp({String? message}) async {
    final id = _id;
    _close(message ?? 'Call ended.');
    if (id != null) await _api.endCall(id);
  }

  void _close(String message) {
    if (_closing) return;
    _closing = true;
    if (_id != null) CallService.instance.markHandled(_id!);
    _cleanUp();
    CallService.showMessage(message);
    // pop() (not maybePop) — the PopScope below would otherwise block it
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  void _cleanUp() {
    _poll?.cancel();
    _tick?.cancel();
    _buzz?.cancel();
    for (final t in _local?.getTracks() ?? <MediaStreamTrack>[]) {
      t.stop();
    }
    _local?.dispose();
    _local = null;
    _pc?.close();
    _pc = null;
    CallService.instance.activeCallId = null;
    CallService.instance.inCall = false;
    if (!kIsWeb) {
      try {
        Helper.setSpeakerphoneOn(false);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    if (!_closing) {
      _closing = true;
      if (_id != null) _api.endCall(_id!);
      _cleanUp();
    }
    _localView.srcObject = null;
    _remoteView.srcObject = null;
    _localView.dispose();
    _remoteView.dispose();
    super.dispose();
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final showRemoteVideo = _isVideo && _hasRemoteVideo;
    final showLocalVideo = _isVideo && _local != null && !_cameraOff;

    return PopScope(
      canPop: _closing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hangUp(); // back button = hang up
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1220),
        body: Stack(
          children: [
            // background
            Positioned.fill(
              child: showRemoteVideo
                  ? RTCVideoView(_remoteView, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(0, -1),
                          radius: 1.3,
                          colors: [Color(0xFF1E3A78), Color(0xFF0B1220)],
                        ),
                      ),
                    ),
            ),
            // plays the other person's voice on the web build
            if (!showRemoteVideo) SizedBox(width: 1, height: 1, child: RTCVideoView(_remoteView)),

            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  if (!showRemoteVideo) ...[
                    Avatar(seed: widget.other, text: MessageRow.initialsOf(widget.other), radius: 52),
                    const SizedBox(height: 18),
                  ],
                  Text(
                    widget.other.split('@').first,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                    ),
                  ),
                  if (!showRemoteVideo) ...[
                    const SizedBox(height: 4),
                    Text(widget.other, style: const TextStyle(color: Colors.white60, fontSize: 14)),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    _statusText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontFeatures: [FontFeature.tabularFigures()],
                      shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                    ),
                  ),
                  const Spacer(),
                  _controls(),
                  const SizedBox(height: 28),
                ],
              ),
            ),

            // my own camera (small, top right)
            if (showLocalVideo)
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                right: 12,
                width: 108,
                height: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: RTCVideoView(_localView,
                      mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    if (_ringingForMe) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundButton(
            icon: Icons.call_end,
            label: 'Decline',
            color: const Color(0xFFE5484D),
            onTap: () => _hangUp(message: 'Call declined.'),
          ),
          _RoundButton(
            icon: _isVideo ? Icons.videocam : Icons.call,
            label: 'Accept',
            color: const Color(0xFF16A36A),
            onTap: _accept,
          ),
        ],
      );
    }
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 18,
      runSpacing: 14,
      children: [
        _RoundButton(
          icon: _muted ? Icons.mic_off : Icons.mic,
          label: _muted ? 'Unmute' : 'Mute',
          active: _muted,
          onTap: _toggleMute,
        ),
        if (_isVideo) ...[
          _RoundButton(
            icon: _cameraOff ? Icons.videocam_off : Icons.videocam,
            label: _cameraOff ? 'Camera on' : 'Camera off',
            active: _cameraOff,
            onTap: _toggleCamera,
          ),
          if (!kIsWeb) _RoundButton(icon: Icons.cameraswitch_outlined, label: 'Flip', onTap: _switchCamera),
        ],
        if (!kIsWeb)
          _RoundButton(
            icon: _speaker ? Icons.volume_up : Icons.volume_down_outlined,
            label: 'Speaker',
            active: _speaker,
            onTap: _toggleSpeaker,
          ),
        _RoundButton(
          icon: Icons.call_end,
          label: _inCall ? 'End' : 'Cancel',
          color: const Color(0xFFE5484D),
          onTap: () => _hangUp(),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool active;

  const _RoundButton({required this.icon, required this.label, required this.onTap, this.color, this.active = false});

  @override
  Widget build(BuildContext context) {
    final bg = color ?? (active ? Colors.white : Colors.white.withValues(alpha: 0.16));
    final fg = color != null ? Colors.white : (active ? const Color(0xFF0B1220) : Colors.white);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: bg,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 62, height: 62, child: Icon(icon, color: fg, size: 28)),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
