import os
import json
import base64
import uuid
from datetime import datetime, timezone
from decimal import Decimal

import boto3

ddb = boto3.resource("dynamodb")
TABLE_NAME = os.environ.get("TABLE_NAME")
table = ddb.Table(TABLE_NAME)

DEFAULT_HEADERS = {
    "content-type": "application/json",
    "access-control-allow-origin": "*",
    "access-control-allow-headers": "content-type",
    "access-control-allow-methods": "GET,POST,PATCH,DELETE,OPTIONS",
}


def _resp(status, body):
    return {
        "statusCode": status,
        "headers": DEFAULT_HEADERS,
        "body": json.dumps(body, default=_coerce_json),
    }


def _coerce_json(value):
    if isinstance(value, Decimal):
        if value % 1 == 0:
            return int(value)
        return float(value)
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")


def _extract_id(pk):
    return pk.split("#", 1)[1] if "#" in pk else pk


def _now_iso():
    return datetime.now(timezone.utc).isoformat()


def lambda_handler(event, context):
    method = (event.get("requestContext", {}).get("http", {}).get("method") or "").upper()
    path = event.get("rawPath") or event.get("requestContext", {}).get("http", {}).get("path") or ""

    if method == "OPTIONS":
        return _resp(200, {"ok": True})

    try:
        if method == "GET" and path.endswith("/items"):
            return list_items()

        if method == "POST" and path.endswith("/items"):
            data = _parse_body(event)
            return create_item(data)

        if method == "PATCH" and path.startswith("/items/"):
            item_id = path.rsplit("/", 1)[-1]
            data = _parse_body(event)
            return update_item(item_id, data)

        if method == "DELETE" and path.startswith("/items/"):
            item_id = path.rsplit("/", 1)[-1]
            return delete_item(item_id)

        return _resp(405, {"message": "method not allowed"})
    except ValueError as err:
        return _resp(400, {"message": str(err)})
    except Exception as err:  # pylint: disable=broad-except
        return _resp(500, {"error": str(err)})


def _parse_body(event):
    body = event.get("body") or ""
    if event.get("isBase64Encoded"):
        body = base64.b64decode(body).decode("utf-8")
    if not body:
        return {}
    try:
        return json.loads(body)
    except json.JSONDecodeError as err:
        raise ValueError("Request body must be valid JSON") from err


def _item_payload(item):
    return {
        "id": _extract_id(item["pk"]),
        "name": item.get("name"),
        "quantity": item.get("quantity"),
        "category": item.get("category"),
        "packed": bool(item.get("packed")),
        "notes": item.get("notes"),
        "created_at": item.get("created_at"),
        "updated_at": item.get("updated_at"),
    }


def list_items():
    response = table.scan()
    items = response.get("Items", [])
    while response.get("LastEvaluatedKey"):
        response = table.scan(ExclusiveStartKey=response["LastEvaluatedKey"])
        items.extend(response.get("Items", []))

    items_prepared = sorted(
        (_item_payload(it) for it in items),
        key=lambda x: x.get("created_at") or "",
        reverse=False,
    )
    return _resp(200, {"items": items_prepared})


def create_item(data):
    name = (data.get("name") or "").strip()
    if not name:
        raise ValueError("Item name is required.")

    quantity = data.get("quantity") or 1
    try:
        quantity = int(quantity)
    except (TypeError, ValueError) as err:
        raise ValueError("Quantity must be an integer.") from err
    if quantity < 1:
        raise ValueError("Quantity must be at least 1.")

    item_id = str(uuid.uuid4())
    now = _now_iso()
    item = {
        "pk": f"ITEM#{item_id}",
        "name": name,
        "quantity": quantity,
        "category": (data.get("category") or "General").strip() or "General",
        "packed": bool(data.get("packed", False)),
        "notes": (data.get("notes") or "").strip(),
        "created_at": now,
        "updated_at": now,
    }
    table.put_item(Item=item)
    return _resp(201, {"item": _item_payload(item)})


def update_item(item_id, data):
    if not item_id:
        raise ValueError("Item id is required.")

    updates = []
    expr_attr_values = {}
    expr_attr_names = {}

    if "name" in data:
        name = (data.get("name") or "").strip()
        if not name:
            raise ValueError("Item name cannot be empty.")
        updates.append("#name = :name")
        expr_attr_values[":name"] = name
        expr_attr_names["#name"] = "name"

    if "quantity" in data:
        try:
            quantity = int(data.get("quantity"))
        except (TypeError, ValueError) as err:
            raise ValueError("Quantity must be an integer.") from err
        if quantity < 1:
            raise ValueError("Quantity must be at least 1.")
        updates.append("quantity = :quantity")
        expr_attr_values[":quantity"] = quantity

    if "category" in data:
        category = (data.get("category") or "").strip() or "General"
        updates.append("category = :category")
        expr_attr_values[":category"] = category

    if "notes" in data:
        notes = (data.get("notes") or "").strip()
        updates.append("notes = :notes")
        expr_attr_values[":notes"] = notes

    if "packed" in data:
        updates.append("packed = :packed")
        expr_attr_values[":packed"] = bool(data.get("packed"))

    updates.append("updated_at = :updated_at")
    expr_attr_values[":updated_at"] = _now_iso()

    update_expression = "SET " + ", ".join(updates)

    update_kwargs = dict(
        Key={"pk": f"ITEM#{item_id}"},
        UpdateExpression=update_expression,
        ExpressionAttributeValues=expr_attr_values,
        ReturnValues="ALL_NEW",
    )
    if expr_attr_names:
        update_kwargs["ExpressionAttributeNames"] = expr_attr_names

    response = table.update_item(**update_kwargs)
    attributes = response.get("Attributes")
    if not attributes:
        return _resp(404, {"message": "Item not found."})
    return _resp(200, {"item": _item_payload(attributes)})


def delete_item(item_id):
    if not item_id:
        raise ValueError("Item id is required.")
    response = table.delete_item(
        Key={"pk": f"ITEM#{item_id}"},
        ReturnValues="ALL_OLD",
    )
    if not response.get("Attributes"):
        return _resp(404, {"message": "Item not found."})
    return _resp(200, {"deleted": True, "id": item_id})