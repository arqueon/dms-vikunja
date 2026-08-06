#!/usr/bin/env python3
"""Small, dependency-free Vikunja API bridge for the DMS plugin.

The DMS surfaces call this process with structured arguments. The API token is
read from Freedesktop Secret Service and never written to DMS settings.
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import re
import secrets
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen


SECRET_SERVICE = "dms-vikunja"
SECRET_KEY = "api-token"
USER_AGENT = "dms-vikunja/0.1.0"
ALLOWED_TASK_FIELDS = {
    "title",
    "description",
    "done",
    "due_date",
    "start_date",
    "end_date",
    "priority",
    "project_id",
    "percent_done",
    "is_favorite",
    "repeat_after",
    "repeat_mode",
    "reminders",
}


class ApiError(RuntimeError):
    def __init__(self, message: str, status: int = 0, code: int | None = None):
        super().__init__(message)
        self.status = status
        self.code = code


def emit(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


def normalize_base_url(value: str) -> str:
    raw = (value or "").strip()
    if not raw:
        raise ApiError("Vikunja server URL is not configured")
    if "://" not in raw:
        raw = "https://" + raw
    parsed = urlsplit(raw)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ApiError("Vikunja server URL must use http:// or https://")
    path = parsed.path.rstrip("/")
    for suffix in ("/api/v1", "/api/v2", "/api"):
        if path.endswith(suffix):
            path = path[: -len(suffix)]
            break
    return urlunsplit((parsed.scheme, parsed.netloc, path.rstrip("/"), "", ""))


def read_token() -> str:
    test_token = os.environ.get("DMS_VIKUNJA_TEST_TOKEN", "").strip()
    if test_token:
        return test_token
    try:
        result = subprocess.run(
            [
                "secret-tool",
                "lookup",
                "service",
                SECRET_SERVICE,
                "key",
                SECRET_KEY,
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
        raise ApiError("Secret Service is unavailable; install secret-tool and unlock the keyring") from exc
    token = result.stdout.strip() if result.returncode == 0 else ""
    if not token:
        raise ApiError("No Vikunja API token is stored in the system keyring")
    return token


def parse_problem(body: bytes, status: int) -> ApiError:
    text = body.decode("utf-8", errors="replace").strip()
    try:
        payload = json.loads(text) if text else {}
    except json.JSONDecodeError:
        payload = {}
    message = payload.get("detail") or payload.get("message") or payload.get("title")
    if not message:
        message = f"Vikunja request failed with HTTP {status}"
    return ApiError(str(message), status=status, code=payload.get("code"))


def request_json(
    base_url: str,
    api_version: str,
    method: str,
    path: str,
    *,
    token: str | None = None,
    params: dict[str, Any] | None = None,
    body: dict[str, Any] | None = None,
    content_type: str = "application/json",
) -> Any:
    query = urlencode(params or {}, doseq=True)
    url = f"{base_url}/api/{api_version}{path}"
    if query:
        url += "?" + query
    headers = {"Accept": "application/json", "User-Agent": USER_AGENT}
    if token:
        headers["Authorization"] = "Bearer " + token
    data = None
    if body is not None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = content_type
    req = Request(url, data=data, headers=headers, method=method)
    try:
        with urlopen(req, timeout=35) as response:
            raw = response.read()
            if not raw:
                return None
            return json.loads(raw.decode("utf-8"))
    except HTTPError as exc:
        raise parse_problem(exc.read(), exc.code) from exc
    except URLError as exc:
        reason = getattr(exc, "reason", exc)
        raise ApiError(f"Cannot reach Vikunja: {reason}") from exc
    except TimeoutError as exc:
        raise ApiError("Vikunja request timed out") from exc
    except json.JSONDecodeError as exc:
        raise ApiError("Vikunja returned invalid JSON") from exc


def server_info(base_url: str) -> dict[str, Any]:
    return request_json(base_url, "v1", "GET", "/info")


def version_tuple(value: str) -> tuple[int, int, int]:
    match = re.search(r"(\d+)\.(\d+)\.(\d+)", value or "")
    if not match:
        return (0, 0, 0)
    return tuple(int(part) for part in match.groups())


def choose_api(preference: str, info: dict[str, Any]) -> str:
    if preference in {"v1", "v2"}:
        return preference
    return "v2" if version_tuple(str(info.get("version", ""))) >= (2, 4, 0) else "v1"


def paginate(
    base_url: str,
    api_version: str,
    path: str,
    token: str,
    params: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    page = 1
    while True:
        page_params = dict(params or {})
        page_params.update({"page": page, "per_page": 1000})
        payload = request_json(
            base_url,
            api_version,
            "GET",
            path,
            token=token,
            params=page_params,
        )
        if api_version == "v2":
            current = payload.get("items", []) if isinstance(payload, dict) else []
            total_pages = int(payload.get("total_pages", 1)) if isinstance(payload, dict) else 1
        else:
            current = payload if isinstance(payload, list) else []
            total_pages = page + 1 if len(current) == 1000 else page
        items.extend(current)
        if page >= total_pages or not current:
            break
        page += 1
        if page > 1000:
            raise ApiError("Pagination limit exceeded while reading Vikunja")
    return items


def context(args: argparse.Namespace, require_token: bool = True) -> tuple[str, dict[str, Any], str, str | None]:
    base_url = normalize_base_url(args.base_url)
    info = server_info(base_url)
    api_version = choose_api(args.api_version, info)
    token = read_token() if require_token else None
    return base_url, info, api_version, token


def parse_patch(raw: str) -> dict[str, Any]:
    try:
        patch = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ApiError("Task update payload is not valid JSON") from exc
    if not isinstance(patch, dict):
        raise ApiError("Task update payload must be an object")
    unknown = sorted(set(patch) - ALLOWED_TASK_FIELDS)
    if unknown:
        raise ApiError("Unsupported task fields: " + ", ".join(unknown))
    if "title" in patch and not str(patch["title"]).strip():
        raise ApiError("Task title cannot be empty")
    return patch


def parse_label_ids(raw: str) -> list[int]:
    if not (raw or "").strip():
        return []
    try:
        values = [int(part.strip()) for part in raw.split(",") if part.strip()]
    except ValueError as exc:
        raise ApiError("Label IDs must be comma-separated integers") from exc
    return list(dict.fromkeys(values))


def replace_labels(base_url: str, api_version: str, token: str, task_id: int, label_ids: list[int]) -> Any:
    method = "PUT" if api_version == "v2" else "POST"
    return request_json(
        base_url,
        api_version,
        method,
        f"/tasks/{task_id}/labels/bulk",
        token=token,
        body={"labels": [{"id": label_id} for label_id in label_ids]},
    )


def local_file_path(value: str) -> Path:
    raw = str(value or "")
    parsed = urlsplit(raw)
    if parsed.scheme:
        if parsed.scheme != "file" or parsed.netloc not in {"", "localhost"}:
            raise ApiError("Only local file selections can be uploaded")
        raw = unquote(parsed.path)
    path = Path(raw).expanduser()
    if not path.is_file():
        raise ApiError(f"Selected file does not exist: {path.name or raw}")
    if not os.access(path, os.R_OK):
        raise ApiError(f"Selected file is not readable: {path.name}")
    return path


def multipart_header(boundary: str, path: Path) -> bytes:
    filename = path.name.replace("\r", "").replace("\n", "").replace('"', "'")
    mime = mimetypes.guess_type(filename)[0] or "application/octet-stream"
    return (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="files"; filename="{filename}"\r\n'
        f"Content-Type: {mime}\r\n\r\n"
    ).encode("utf-8")


def request_multipart(
    base_url: str,
    api_version: str,
    path: str,
    token: str,
    files: list[Path],
) -> Any:
    boundary = "----dms-vikunja-" + secrets.token_hex(16)
    headers_and_paths = [(multipart_header(boundary, path), path) for path in files]
    closing = f"--{boundary}--\r\n".encode("ascii")
    content_length = len(closing) + sum(
        len(header) + path.stat().st_size + 2
        for header, path in headers_and_paths
    )

    def chunks():
        for header, file_path in headers_and_paths:
            yield header
            with file_path.open("rb") as handle:
                while chunk := handle.read(1024 * 1024):
                    yield chunk
            yield b"\r\n"
        yield closing

    url = f"{base_url}/api/{api_version}{path}"
    headers = {
        "Accept": "application/json",
        "Authorization": "Bearer " + token,
        "Content-Length": str(content_length),
        "Content-Type": f"multipart/form-data; boundary={boundary}",
        "User-Agent": USER_AGENT,
    }
    req = Request(url, data=chunks(), headers=headers, method="POST")
    try:
        with urlopen(req, timeout=300) as response:
            raw = response.read()
            return json.loads(raw.decode("utf-8")) if raw else {}
    except HTTPError as exc:
        raise parse_problem(exc.read(), exc.code) from exc
    except URLError as exc:
        reason = getattr(exc, "reason", exc)
        raise ApiError(f"Cannot reach Vikunja: {reason}") from exc
    except TimeoutError as exc:
        raise ApiError("Vikunja attachment upload timed out") from exc
    except json.JSONDecodeError as exc:
        raise ApiError("Vikunja returned invalid attachment upload JSON") from exc


def cmd_sync(args: argparse.Namespace) -> None:
    base_url, info, api_version, token = context(args)
    assert token is not None
    task_params: dict[str, Any] = {}
    if not args.include_done:
        task_params["filter"] = "done = false"
    projects = paginate(base_url, api_version, "/projects", token)
    labels = paginate(base_url, api_version, "/labels", token)
    tasks = paginate(base_url, api_version, "/tasks", token, task_params)
    emit(
        {
            "ok": True,
            "base_url": base_url,
            "api_version": api_version,
            "server_version": info.get("version", ""),
            "projects": projects,
            "labels": labels,
            "tasks": tasks,
            "synced_at": datetime.now(timezone.utc).isoformat(),
        }
    )


def cmd_check(args: argparse.Namespace) -> None:
    base_url, info, api_version, token = context(args)
    assert token is not None
    user = request_json(base_url, api_version, "GET", "/user", token=token)
    emit(
        {
            "ok": True,
            "base_url": base_url,
            "api_version": api_version,
            "server_version": info.get("version", ""),
            "username": user.get("username", "") if isinstance(user, dict) else "",
        }
    )


def cmd_info(args: argparse.Namespace) -> None:
    base_url, info, api_version, _ = context(args, require_token=False)
    emit(
        {
            "ok": True,
            "base_url": base_url,
            "api_version": api_version,
            "server_version": info.get("version", ""),
        }
    )


def cmd_create(args: argparse.Namespace) -> None:
    base_url, info, api_version, token = context(args)
    assert token is not None
    title = args.title.strip()
    if not title:
        raise ApiError("Task title cannot be empty")
    body: dict[str, Any] = {"title": title, "priority": args.priority}
    if args.due_date:
        body["due_date"] = args.due_date
    method = "POST" if api_version == "v2" else "PUT"
    task = request_json(
        base_url,
        api_version,
        method,
        f"/projects/{args.project_id}/tasks",
        token=token,
        body=body,
    )
    label_ids = parse_label_ids(args.label_ids)
    if label_ids:
        replace_labels(base_url, api_version, token, int(task["id"]), label_ids)
    emit(
        {
            "ok": True,
            "api_version": api_version,
            "server_version": info.get("version", ""),
            "task": task,
        }
    )


def cmd_save(args: argparse.Namespace) -> None:
    base_url, info, api_version, token = context(args)
    assert token is not None
    patch = parse_patch(args.patch)
    method = "PATCH" if api_version == "v2" else "POST"
    content_type = "application/merge-patch+json" if api_version == "v2" else "application/json"
    task = request_json(
        base_url,
        api_version,
        method,
        f"/tasks/{args.task_id}",
        token=token,
        body=patch,
        content_type=content_type,
    )
    if args.label_ids is not None:
        replace_labels(
            base_url,
            api_version,
            token,
            args.task_id,
            parse_label_ids(args.label_ids),
        )
    emit(
        {
            "ok": True,
            "api_version": api_version,
            "server_version": info.get("version", ""),
            "task": task,
        }
    )


def cmd_delete(args: argparse.Namespace) -> None:
    base_url, info, api_version, token = context(args)
    assert token is not None
    request_json(
        base_url,
        api_version,
        "DELETE",
        f"/tasks/{args.task_id}",
        token=token,
    )
    emit(
        {
            "ok": True,
            "api_version": api_version,
            "server_version": info.get("version", ""),
            "deleted_task_id": args.task_id,
        }
    )


def cmd_upload_attachments(args: argparse.Namespace) -> None:
    base_url, info, api_version, token = context(args)
    assert token is not None
    if api_version != "v2":
        raise ApiError("Attachment upload requires Vikunja 2.4 or newer (API v2)")
    try:
        selected = json.loads(args.file_urls)
    except json.JSONDecodeError as exc:
        raise ApiError("Attachment selection is not valid JSON") from exc
    if not isinstance(selected, list) or not selected:
        raise ApiError("Choose at least one file to attach")

    paths: list[Path] = []
    errors: list[dict[str, Any]] = []
    for value in selected:
        try:
            paths.append(local_file_path(str(value)))
        except ApiError as exc:
            errors.append({"message": str(exc), "code": exc.code})

    result: dict[str, Any] = {}
    if paths:
        payload = request_multipart(
            base_url,
            api_version,
            f"/tasks/{args.task_id}/attachments",
            token,
            paths,
        )
        result = payload if isinstance(payload, dict) else {}
    uploaded = result.get("success") if isinstance(result.get("success"), list) else []
    remote_errors = result.get("errors") if isinstance(result.get("errors"), list) else []
    emit(
        {
            "ok": True,
            "api_version": api_version,
            "server_version": info.get("version", ""),
            "uploaded": uploaded,
            "errors": errors + remote_errors,
        }
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Vikunja bridge for dms-vikunja")
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--api-version", choices=("auto", "v1", "v2"), default="auto")
    sub = parser.add_subparsers(dest="command", required=True)

    sync = sub.add_parser("sync")
    sync.add_argument("--include-done", action="store_true")
    sync.set_defaults(handler=cmd_sync)

    check = sub.add_parser("check")
    check.set_defaults(handler=cmd_check)

    info = sub.add_parser("info")
    info.set_defaults(handler=cmd_info)

    create = sub.add_parser("create-task")
    create.add_argument("project_id", type=int)
    create.add_argument("title")
    create.add_argument("due_date")
    create.add_argument("priority", type=int)
    create.add_argument("label_ids")
    create.set_defaults(handler=cmd_create)

    save = sub.add_parser("save-task")
    save.add_argument("task_id", type=int)
    save.add_argument("patch")
    save.add_argument("label_ids", nargs="?", default=None)
    save.set_defaults(handler=cmd_save)

    delete = sub.add_parser("delete-task")
    delete.add_argument("task_id", type=int)
    delete.set_defaults(handler=cmd_delete)

    upload = sub.add_parser("upload-attachments")
    upload.add_argument("task_id", type=int)
    upload.add_argument("file_urls")
    upload.set_defaults(handler=cmd_upload_attachments)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        args.handler(args)
        return 0
    except ApiError as exc:
        emit(
            {
                "ok": False,
                "error": str(exc),
                "status": exc.status,
                "code": exc.code,
            }
        )
        return 1
    except Exception as exc:  # Keep QML errors structured without hiding the failure.
        emit({"ok": False, "error": f"Unexpected bridge error: {exc}", "status": 0})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
