import httpx # Replace requests
import asyncio # Import asyncio
import logging
# import time # Replaced by asyncio.sleep
import json
from typing import Dict, Any, Optional, List, AsyncIterator # Added AsyncIterator
import base64
import os
from pathlib import Path
import contextlib # For async context manager with files

from .config import Settings

logger = logging.getLogger(__name__)

API_BASE_URL = "https://apis.roblox.com/"
OPERATIONS_API_BASE_URL = "https://apis.roblox.com/operations/v1/"
DEVELOP_API_BASE_URL = "https://develop.roblox.com/" # Added for publish
POLLING_BASE_URL = "https://operations.roblox.com/" # Hypothetical base URL for polling

class RobloxApiError(Exception):
    """Custom exception for Roblox API errors."""
    def __init__(self, message, status_code=None, response_data=None):
        super().__init__(message)
        self.status_code = status_code
        self.response_data = response_data

class RobloxClient:
    def __init__(self, config: Settings):
        if not config:
            raise ValueError("Configuration is required to initialize RobloxClient")
        self.api_key = config.roblox_api_key
        self.universe_id = config.roblox_universe_id
        self.place_id = config.roblox_place_id # Default place ID
        
        # Initialize httpx.AsyncClient
        headers = {
            "x-api-key": self.api_key,
            "Content-Type": "application/json",
            "Accept": "application/json" # Generally expect JSON responses
        }
        self.client = httpx.AsyncClient(headers=headers, timeout=30.0) # Default timeout
        logger.info("RobloxClient initialized with httpx.AsyncClient.")

    async def _request(self, method: str, url: str,
                 params: Optional[Dict] = None, json_data: Optional[Dict] = None,
                 data: Optional[Any] = None, headers: Optional[Dict] = None,
                 files: Optional[Dict] = None, # httpx uses 'files', 'data' for form data, 'content' for raw bytes
                 content: Optional[bytes] = None, # For raw content like datastore set
                 timeout: Optional[float] = 30.0 # Allow per-request timeout override
                 ) -> Dict[str, Any]:
        """Async internal helper to make HTTP requests to Roblox API using httpx."""
        request_headers = self.client.headers.copy() # Start with client defaults
        if headers:
            request_headers.update(headers)

        # httpx handles Content-Type based on data/json/files/content, but let's remove if files specified
        if files:
            request_headers.pop("Content-Type", None)
        # If raw content or data (form) is provided, httpx might need explicit Content-Type if not default
        # If data is dict, httpx assumes form data, otherwise treats as bytes/string based on Content-Type
        # If content is bytes, Content-Type should be set appropriately in headers if needed

        max_retries = 3
        retry_delay = 1.0 # seconds, float for asyncio.sleep

        for attempt in range(max_retries):
            try:
                logger.debug(f"Sending {method} request to {url} (Attempt {attempt+1})")
                response = await self.client.request(
                    method=method,
                    url=url,
                    params=params,
                    json=json_data,
                    data=data, # For form data (dict)
                    files=files,
                    content=content, # For raw bytes/strings
                    headers=request_headers,
                    timeout=timeout
                )

                logger.debug(f"Received response: Status {response.status_code}, Headers: {response.headers}")

                # Handle Rate Limits (429)
                if response.status_code == 429:
                    retry_after_str = response.headers.get("Retry-After")
                    try:
                        delay = float(retry_after_str) if retry_after_str else retry_delay
                    except (ValueError, TypeError):
                        delay = retry_delay
                    # Ensure non-negative delay
                    delay = max(0, delay)
                    logger.warning(f"Rate limit hit (429) on attempt {attempt + 1}/{max_retries}. Retrying in {delay:.2f}s...")
                    await asyncio.sleep(delay)
                    # Exponential backoff, but ensure it respects Retry-After if larger
                    retry_delay = max(retry_delay * 2, delay) 
                    continue

                # Check for other errors
                response.raise_for_status() # Raises httpx.HTTPStatusError for 4xx/5xx

                # Try to parse JSON, handle cases with no content
                if response.status_code == 204: # No Content
                     return {}
                if response.content:
                    try:
                        # Use response.json() which handles decoding
                        return response.json()
                    except json.JSONDecodeError:
                        logger.warning(f"Non-JSON response received from {url}: {response.text[:100]}...")
                        # Return raw text if JSON parsing fails but request was successful
                        return {"raw_content": response.text} 
                else:
                    # Successful status code but no content (e.g., sometimes 200 OK with empty body)
                    return {}

            except httpx.HTTPStatusError as e:
                error_body = e.response.text
                try:
                    error_details = e.response.json()
                    message = f"HTTP Error {e.response.status_code}: {error_details.get('message', error_body)}"
                    response_data = error_details
                except json.JSONDecodeError:
                    message = f"HTTP Error {e.response.status_code}: {error_body}"
                    response_data = error_body
                
                # Handle 404 specifically for certain operations if needed (e.g., datastore get)
                # The caller method can decide how to handle specific status codes from RobloxApiError
                logger.error(f"HTTP Status Error from {url}: {message}")
                raise RobloxApiError(message, status_code=e.response.status_code, response_data=response_data) from e
            
            except httpx.RequestError as e: # Catches broader network issues, timeouts etc.
                logger.error(f"Request Error for {url} on attempt {attempt + 1}: {e}")
                if attempt == max_retries - 1:
                    raise RobloxApiError(f"Request Failed after {max_retries} attempts: {e}") from e
                await asyncio.sleep(retry_delay)
                retry_delay *= 2

        # Should not be reached if max_retries > 0
        raise RobloxApiError(f"Request failed after {max_retries} retries.")

    # --- Luau Execution --- 
    async def _poll_operation(self, operation_path: str, timeout: int = 90) -> Dict[str, Any]:
        """Async polls a long-running operation until completion or timeout."""
        loop = asyncio.get_event_loop()
        start_time = loop.time()
        poll_interval = 1.0 # Start polling after 1 second

        # Construct polling URL: BASE/cloud/v2/PATH
        operation_url = f"{API_BASE_URL.rstrip('/')}/cloud/v2/{operation_path.lstrip('/')}"
        logger.info(f"Constructed polling URL (with /cloud/v2/): {operation_url}")

        while loop.time() - start_time < timeout:
            try:
                logger.debug(f"Polling operation: {operation_url}")
                op_status = await self._request("GET", operation_url)

                # --- REVISED COMPLETION CHECK ---
                current_state = op_status.get('state')
                if current_state in ['COMPLETE', 'FAILED', 'CANCELLED'] or op_status.get("error"):
                    logger.info(f"Operation {operation_path} reached terminal state: {current_state}")
                    return op_status # Return the final status object
                else:
                    # Log current state if not done
                    logger.debug(f"Operation {operation_path} not complete yet. State: {current_state or 'Unknown'}")
                # --- END REVISED COMPLETION CHECK ---

            except RobloxApiError as e:
                logger.error(f"API Error polling operation {operation_path}: {e}")
                raise
            except Exception as e:
                 logger.error(f"Unexpected error polling operation {operation_path}: {e}", exc_info=True)
                 raise RobloxApiError(f"Unexpected polling error: {e}") from e

            await asyncio.sleep(poll_interval)
            poll_interval = min(poll_interval * 1.5, 5.0) # Increase delay up to 5 seconds

        raise RobloxApiError(f"Operation {operation_path} timed out after {timeout} seconds.", status_code=408)

    async def call_luau(self, script: str, target_place_id: Optional[int] = None, execution_timeout_secs: int = 30) -> Dict[str, Any]:
        """Async calls the Luau Execution API and waits for the result."""
        place_id = target_place_id or self.place_id
        if not place_id:
            raise ValueError("Target Place ID must be provided either in config or as argument.")

        endpoint = f"cloud/v2/universes/{self.universe_id}/places/{place_id}/luau-execution-session-tasks"
        url = f"{API_BASE_URL.rstrip('/')}/{endpoint.lstrip('/')}"
        payload = {
            "script": script,
            "timeout": f"{execution_timeout_secs}s"
        }

        logger.info(f"Initiating Luau execution for place {place_id}...")
        try:
            task_response = await self._request("POST", url, json_data=payload)
            logger.info(f"Received task response from /execute: {task_response}")
            operation_path = task_response.get("path")
            if not operation_path:
                 raise RobloxApiError("Luau execution task response did not contain 'path'.", response_data=task_response)

            logger.info(f"Luau task created, operation path: {operation_path}. Polling for result...")
            operation_result = await self._poll_operation(operation_path, timeout=execution_timeout_secs + 30)
            logger.debug(f"Full operation result from poll: {operation_result}")

            # --- REVISED RESULT PROCESSING (Fetch Logs) ---
            final_state = operation_result.get('state')
            if final_state == 'FAILED' or operation_result.get("error"):
                error_info = operation_result.get("error", {"message": f"Task failed with state {final_state} but no error details."}) 
                logger.error(f"Luau execution failed: {error_info}")
                error_response_data = error_info if isinstance(error_info, (dict, list, str, int, float, bool, type(None))) else str(error_info)
                raise RobloxApiError(f"Luau script execution error: {error_info.get('message', 'Unknown error')}", response_data=error_response_data)
            
            elif final_state != 'COMPLETE':
                # Handle unexpected states like CANCELLED or QUEUED (if polling timeout was too short?)
                raise RobloxApiError(f"Luau task ended in unexpected state: {final_state}", response_data=operation_result)

            # If state is COMPLETE, fetch logs
            logger.info(f"Task {operation_path} complete. Fetching logs...")
            logs_url = f"{API_BASE_URL.rstrip('/')}/cloud/v2/{operation_path.lstrip('/')}/logs" # Construct logs URL
            try:
                # --- ADD DEBUG LOGGING ---
                logger.debug(f"Fetching logs from: {logs_url}")
                logs_response = await self._request("GET", logs_url)
                logger.debug(f"Received raw logs_response (type {type(logs_response)}): {logs_response}")
                # --- END DEBUG LOGGING ---
                
                # Logs might be nested under "luauExecutionSessionTaskLogs"
                log_chunks = logs_response.get("luauExecutionSessionTaskLogs", [])
                # --- ADD DEBUG LOGGING ---
                logger.debug(f"Extracted log_chunks (type {type(log_chunks)}): {log_chunks}")
                # --- END DEBUG LOGGING ---
                messages = []
                if log_chunks and isinstance(log_chunks, list):
                    # --- ADD DEBUG LOGGING ---
                    for i, chunk in enumerate(log_chunks):
                        logger.debug(f"Processing chunk {i} (type {type(chunk)}): {chunk}")
                        # --- END DEBUG LOGGING ---
                        messages.extend(chunk.get("messages", []))
                
                # --- Modified Log Processing Logic --- 
                if not messages:
                    # Check if the raw response was just '[]' from _request's fallback
                    raw_output_from_logs = logs_response.get("raw_content") if isinstance(logs_response, dict) else None
                    if raw_output_from_logs == "[]":
                        logger.warning("Luau script completed but returned only '[]'. Returning empty dict.")
                        return {} # Return empty dict instead of the string "[]" or the "no messages" dict
                    else:
                        logger.warning(f"Luau script completed but no log messages found or parsed at {logs_url}. Raw response: {logs_response}")
                        return {"output": "", "parsed_json": None} # Indicate empty/unparsed output

                # --- Process all messages, prioritize last JSON --- 
                all_logs_str = "\n".join(map(str, messages))
                parsed_json_output = None
                last_message = messages[-1]

                # Attempt to parse the last message as JSON
                if isinstance(last_message, str) and last_message.strip().startswith('{') and last_message.strip().endswith('}'):
                    try:
                        parsed_json_output = json.loads(last_message)
                        logger.info(f"Successfully JSON-decoded final log message: {json.dumps(parsed_json_output)[:150]}...")
                    except json.JSONDecodeError:
                        logger.warning(f"Final log message looked like JSON but failed to parse: {last_message[:150]}...")
                        # Keep parsed_json_output as None
                
                # Return based on whether final JSON was parsed
                if parsed_json_output is not None:
                    # If last message was valid JSON, return the parsed object
                    return parsed_json_output 
                else:
                    # If last message wasn't JSON (or failed parse), return concatenated logs
                    logger.info(f"Script output appears to be plain text. Returning concatenated logs.")
                    # We return the raw string directly now, not nested in a dict
                    return all_logs_str 
                # --- End Modified Log Processing Logic --- 

            except RobloxApiError as log_err:
                logger.error(f"Failed to fetch logs for completed task {operation_path}: {log_err}")
                raise RobloxApiError(f"Task completed but failed to fetch logs: {log_err}", response_data=log_err.response_data) from log_err
            except Exception as e:
                logger.exception(f"Unexpected error processing logs for {operation_path}")
                raise RobloxApiError(f"Unexpected error processing logs: {e}") from e
            # --- END REVISED RESULT PROCESSING ---
            
        except RobloxApiError as e:
            logger.error(f"Failed to execute Luau script: {e}")
            raise # Re-raise the specific API error

    # --- Datastore --- 
    async def get_datastore_entry(self, datastore_name: str, entry_key: str, scope: str = "global") -> Any:
        """Async gets an entry from a standard datastore. Returns the decoded JSON value or raw text."""
        logger.info(f"Getting datastore entry '{entry_key}' from '{datastore_name}' (scope: {scope})")
        endpoint = f"datastores/v1/universes/{self.universe_id}/standard-datastores/datastore/entries/entry"
        url = f"{API_BASE_URL.rstrip('/')}/{endpoint.lstrip('/')}"
        params = {
            "datastoreName": datastore_name,
            "scope": scope,
            "entryKey": entry_key
        }
        try:
            # Use the _request method now which handles errors and retries
            # Expecting raw text or JSON directly from this endpoint
            response = await self._request("GET", url, params=params, timeout=15.0) 
            
            # _request now returns dict, check for raw_content if JSON failed
            if "raw_content" in response:
                logger.warning(f"Datastore value for {entry_key} is not valid JSON. Returning raw text.")
                return response["raw_content"]
            elif response == {}: # Should not happen for GET with content, but check
                 logger.warning(f"Datastore GET for {entry_key} returned empty response dict.")
                 return None
            else:
                 # If it's not raw_content and not empty, it should be parsed JSON
                 # The API returns the value directly, not nested in a dict
                 return response 

        except RobloxApiError as e:
            if e.status_code == 404:
                logger.info(f"Datastore entry '{entry_key}' not found (404).")
                return None # Return None if key doesn't exist
            else:
                # Re-raise other API errors
                raise
        except Exception as e:
             logger.error(f"Unexpected error getting datastore entry '{entry_key}': {e}", exc_info=True)
             raise RobloxApiError(f"Unexpected error: {e}") from e

    async def set_datastore_entry(self, datastore_name: str, entry_key: str, value: Any, 
                              scope: str = "global", 
                              match_version: Optional[str] = None, 
                              exclude_previous_value: bool = False,
                              user_ids: Optional[List[int]] = None, # For user attributes
                              attributes: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Async sets an entry in a standard datastore. Value should be JSON serializable."""
        logger.info(f"Setting datastore entry '{entry_key}' in '{datastore_name}' (scope: {scope})")
        endpoint = f"datastores/v1/universes/{self.universe_id}/standard-datastores/datastore/entries/entry"
        url = f"{API_BASE_URL.rstrip('/')}/{endpoint.lstrip('/')}"
        params = {
            "datastoreName": datastore_name,
            "scope": scope,
            "entryKey": entry_key
        }
        # Headers specific to this request
        request_headers = {
            "Content-Type": "application/json" # Roblox expects JSON string as data content
        }
        if match_version:
            params["matchVersion"] = match_version
        if exclude_previous_value:
            params["exclusiveCreate"] = "true"
        
        if user_ids or attributes:
             metadata = {}
             if user_ids: metadata["roblox-entry-userids"] = json.dumps(user_ids)
             if attributes: metadata["roblox-entry-attributes"] = json.dumps(attributes)
             encoded_metadata = base64.b64encode(json.dumps(metadata).encode()).decode()
             request_headers["roblox-entry-metadata"] = encoded_metadata

        try:
            json_string_value = json.dumps(value)
            # Send JSON string as raw content bytes
            content_bytes = json_string_value.encode('utf-8')
            # Use await for async _request
            result = await self._request(
                "POST", url, 
                params=params, 
                content=content_bytes, # Use content for raw bytes
                headers=request_headers
            )
            return result # Should contain version info on success
        except json.JSONDecodeError:
             raise ValueError("Value provided is not JSON serializable.")
        except Exception as e:
            logger.error(f"Error setting datastore entry '{entry_key}': {e}", exc_info=True)
            raise # Re-raise original or wrap in RobloxApiError if needed

    async def delete_datastore_entry(self, datastore_name: str, entry_key: str, scope: str = "global") -> None:
        """Async deletes an entry from a standard datastore."""
        logger.info(f"Deleting datastore entry '{entry_key}' from '{datastore_name}' (scope: {scope})")
        endpoint = f"datastores/v1/universes/{self.universe_id}/standard-datastores/datastore/entries/entry"
        url = f"{API_BASE_URL.rstrip('/')}/{endpoint.lstrip('/')}"
        params = {
            "datastoreName": datastore_name,
            "scope": scope,
            "entryKey": entry_key
        }
        try:
            # Use await. Expects 204 No Content on success, _request returns {}
            await self._request("DELETE", url, params=params)
            logger.info(f"Deletion request successful for entry '{entry_key}'.")
        except RobloxApiError as e:
             if e.status_code == 404:
                  # Log info but don't raise error if trying to delete non-existent key
                  logger.info(f"Entry '{entry_key}' not found during delete attempt (404).")
                  return # Treat as success (idempotent delete)
             else:
                  logger.error(f"API error deleting entry '{entry_key}': {e}")
                  raise # Re-raise other errors
        except Exception as e:
             logger.error(f"Unexpected error deleting entry '{entry_key}': {e}", exc_info=True)
             raise RobloxApiError(f"Unexpected error during delete: {e}") from e


    async def list_datastores(self, prefix: Optional[str] = None, limit: Optional[int] = None, cursor: Optional[str] = None) -> Dict[str, Any]:
        """Async lists standard datastores in the universe."""
        logger.info(f"Listing datastores (prefix: {prefix}, limit: {limit})")
        endpoint = f"datastores/v1/universes/{self.universe_id}/standard-datastores"
        url = f"{API_BASE_URL.rstrip('/')}/{endpoint.lstrip('/')}"
        params = {}
        if prefix: params["prefix"] = prefix
        if limit: params["limit"] = limit
        if cursor: params["cursor"] = cursor
        
        # Use await
        return await self._request("GET", url, params=params)
        
    # --- Assets --- 
    
    # Helper for async file opening
    @contextlib.asynccontextmanager
    async def _open_asset_file(self, file_path: str) -> AsyncIterator[tuple]:
        # This basic version just opens synchronously, but structure allows async later if needed
        # For true async file I/O, libraries like aiofiles would be needed.
        # httpx can handle sync file-like objects passed to 'files'.
        file_name = Path(file_path).name
        content_map = {
            ".fbx": "application/octet-stream", ".obj": "application/octet-stream",
            ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
            ".mp3": "audio/mpeg", ".ogg": "audio/ogg",
        }
        file_ext = Path(file_path).suffix.lower()
        content_type = content_map.get(file_ext, "application/octet-stream")
        
        try:
            # Open synchronously for now, httpx handles it
            f = open(file_path, 'rb') 
            yield (file_name, f, content_type)
        finally:
            if 'f' in locals() and f:
                 f.close()


    async def upload_asset(self, file_path: str, asset_type: str, display_name: str, description: str = "") -> Dict[str, Any]:
        """Async uploads a file as a new asset (e.g., Model, Image, Audio)."""
        if not os.path.exists(file_path): # Keep sync check for existence
            raise FileNotFoundError(f"File not found at path: {file_path}")

        logger.info(f"Uploading asset '{display_name}' ({asset_type}) from file '{Path(file_path).name}'")
        asset_api_url = "https://apis.roblox.com/assets/v1/assets" 

        asset_creation_request = {
            "assetType": asset_type,
            "displayName": display_name,
            "description": description,
            "creationContext": { "creator": { "userId": "me" } } # Placeholder, refine if needed
        }
        
        # Prepare headers, remove default Content-Type for multipart
        upload_headers = self.client.headers.copy()
        upload_headers.pop('Content-Type', None)
        # Accept header might already be set globally, but ensure it's correct
        upload_headers['Accept'] = 'application/json' 

        try:
            # Use the async context manager to handle the file
            async with self._open_asset_file(file_path) as file_info:
                # file_info is (file_name, file_object, content_type)
                file_name, file_obj, content_type = file_info
                
                files_payload = {
                    'request': (None, json.dumps(asset_creation_request), 'application/json'),
                    'fileContent': (file_name, file_obj, content_type)
                }

                # Make the request using the client directly (or adapt _request if preferred for retries)
                # Using client directly for simplicity with multipart files
                response = await self.client.post(
                    asset_api_url, 
                    files=files_payload, 
                    headers=upload_headers, 
                    timeout=120.0 # Longer timeout for uploads
                )
                response.raise_for_status() # Check for HTTP errors

                op_data = response.json()
                operation_path = op_data.get('path')
                if not operation_path:
                     raise RobloxApiError("Asset upload did not return an operation path.", response_data=op_data)

                logger.info(f"Asset upload initiated. Operation path: {operation_path}. Polling...")
                # Use await for async poll
                final_result = await self._poll_operation(operation_path, timeout=300)

                if final_result.get("error"):
                    error_info = final_result["error"]
                    logger.error(f"Asset processing failed: {error_info}")
                    raise RobloxApiError(f"Asset processing error: {error_info.get('message', 'Unknown error')}", response_data=error_info)

                asset_id = final_result.get("response", {}).get("assetId")
                if not asset_id: asset_id = final_result.get("metadata", {}).get("assetId") # Fallback check
                
                if asset_id:
                     logger.info(f"Asset upload successful. Asset ID: {asset_id}")
                     return {"assetId": asset_id, "operationResult": final_result}
                else:
                     raise RobloxApiError("Asset upload finished but failed to retrieve Asset ID.", response_data=final_result)

        except httpx.HTTPStatusError as e:
            raise RobloxApiError(f"HTTP Error uploading asset: {e.response.status_code}", status_code=e.response.status_code, response_data=e.response.text) from e
        except httpx.RequestError as e:
            logger.error(f"Request failed during asset upload: {e}", exc_info=True)
            raise RobloxApiError(f"Asset upload request failed: {e}") from e
        except FileNotFoundError as e: # Catch FileNotFoundError specifically
             raise # Re-raise it as it's a client-side error
        except Exception as e:
             logger.exception("Unexpected error during asset upload.")
             raise RobloxApiError(f"Unexpected upload error: {e}") from e

    async def get_asset_details(self, asset_id: int) -> Dict[str, Any]:
        """Async gets details for a specific asset ID."""
        logger.info(f"Getting details for asset ID: {asset_id}")
        # Placeholder - requires correct endpoint
        # endpoint = f"assets/v1/assets/{asset_id}"
        # url = f"{API_BASE_URL.rstrip('/')}/{endpoint.lstrip('/')}" 
        # return await self._request("GET", url)
        raise NotImplementedError("get_asset_details API call not fully implemented - requires correct endpoint.")

    async def list_assets(self, asset_types: Optional[List[str]] = None, 
                      filter_keyword: Optional[str] = None, 
                      limit: Optional[int] = None, 
                      cursor: Optional[str] = None) -> Dict[str, Any]:
        """Async lists assets owned by the user (or context), potentially filtered."""
        logger.info(f"Listing assets (types: {asset_types}, filter: {filter_keyword}, limit: {limit})")
        # Placeholder - requires correct endpoint
        # endpoint = "inventory/v1/..." 
        # url = f"{API_BASE_URL.rstrip('/')}/{endpoint.lstrip('/')}" 
        # params = {...}
        # return await self._request("GET", url, params=params)
        raise NotImplementedError("list_assets API call not fully implemented - requires correct endpoint.")

    # --- Publishing --- 
    async def publish_place(self, target_place_id: Optional[int] = None, version_type: str = "Saved") -> Dict[str, Any]:
        """Async publishes the specified place ID. Version type can be 'Saved' or 'Published'."""
        place_id = target_place_id or self.place_id
        if not place_id:
            raise ValueError("Target Place ID must be provided either in config or as argument.")
        if version_type not in ["Saved", "Published"]:
             raise ValueError("Invalid version_type. Must be 'Saved' or 'Published'.")

        logger.info(f"Publishing place {place_id} as version type '{version_type}'...")
        endpoint = f"v1/universes/{self.universe_id}/places/{place_id}/versions"
        url = f"{DEVELOP_API_BASE_URL.rstrip('/')}/{endpoint.lstrip('/')}" # Use Develop API base
        params = {"versionType": version_type}
        
        # Use await
        return await self._request("POST", url, params=params)

    async def close_session(self):
        """Async closes the underlying httpx client session."""
        await self.client.aclose()
        logger.info("Vibe Blocks MCP httpx session closed.") 