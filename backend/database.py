"""database.py — MongoDB connection, collections and indexes.

Collections (tables in MongoDB are called "collections"):

users      one document per account
           {_id, username, email, password_hash, account_type,
            created_at, expires_at, status}

messages   one document per email (the actual content, stored once)
           {_id, sender_id, sender_email, to_emails, recipient_ids,
            subject, body, attachments: [...], is_draft, created_at}

mailboxes  one document per USER per message: that user's own copy
           of folder / read / star state. If Ali deletes an email,
           Sara's copy is not affected.
           {_id, user_id, message_id, folder, previous_folder, is_read,
            is_starred, from_email, to_emails, subject, snippet,
            search_text, has_attachments, created_at}
"""
from pymongo import ASCENDING, DESCENDING, MongoClient
from gridfs import GridFS

from config import Config, check_config

check_config()

client = MongoClient(Config.MONGODB_URI, tz_aware=True, serverSelectionTimeoutMS=8000)
db = client[Config.MONGODB_DATABASE]

users = db["users"]
messages = db["messages"]
mailboxes = db["mailboxes"]
domains = db["domains"]
addresses = db["addresses"]
# Attachment files are stored inside MongoDB (GridFS), because the online server's disk is temporary
attachment_files = GridFS(db, collection="attachment_files")


def init_indexes():
    # unique=True means MongoDB refuses a second user with the same name/email
    users.create_index("username", unique=True)
    users.create_index("email", unique=True)
    users.create_index("expires_at")

    # Speed up "show my inbox, newest first" and "show my starred"
    mailboxes.create_index([("user_id", ASCENDING), ("folder", ASCENDING), ("created_at", DESCENDING)])
    mailboxes.create_index([("user_id", ASCENDING), ("is_starred", ASCENDING), ("created_at", DESCENDING)])
    mailboxes.create_index("message_id")

    messages.create_index("sender_id")
    messages.create_index("attachments.id")

    # A user can add a domain only once; a domain can be VERIFIED by only one account
    domains.create_index([("owner_id", ASCENDING), ("name", ASCENDING)], unique=True)
    domains.create_index("name", unique=True, partialFilterExpression={"status": "verified"})
    
    # Each custom address (like info@nimranoor.site) can exist only once
    addresses.create_index("email", unique=True)
    addresses.create_index("domain_id")
    addresses.create_index("user_id")

def ping():
    client.admin.command("ping")