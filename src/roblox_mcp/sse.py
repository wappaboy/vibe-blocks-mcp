import logging
from mcp.server.fastmcp import FastMCP
from mcp.server.sse import SseServerTransport
from starlette.applications import Starlette
from starlette.routing import Mount, Route

logger = logging.getLogger(__name__)

def create_sse_server(mcp: FastMCP):
    """Create a Starlette app that handles SSE connections and message handling for MCP."""
    # Define the base path for message posting (relative to where this app is mounted)
    # If mounted at '/', messages go to /messages/
    # If mounted at '/mcp_sse', messages go to /mcp_sse/messages/
    message_post_path = "/messages/"
    transport = SseServerTransport(message_post_path)

    # Define handler function for the SSE connection endpoint
    async def handle_sse(request):
        logger.info(f"SSE connection established from {request.client}")
        try:
            async with transport.connect_sse(
                request.scope, request.receive, request._send
            ) as streams:
                # Run the core MCP server logic using the streams provided by the SSE transport
                await mcp._mcp_server.run(
                    streams[0], streams[1], mcp._mcp_server.create_initialization_options()
                )
        except Exception as e:
            logger.error(f"Error during SSE MCP session: {e}", exc_info=True)
        finally:
            logger.info(f"SSE connection closed for {request.client}")


    # Create Starlette routes
    # The '/sse/' endpoint handles the initial GET request to establish the SSE connection.
    # The '/messages/' endpoint handles the POST requests from the client to send MCP messages *after* the SSE connection is up.
    routes = [
        Route("/sse/", endpoint=handle_sse),
        Mount(message_post_path, app=transport.handle_post_message),
    ]

    # Create and return the Starlette app dedicated to handling SSE transport
    sse_app = Starlette(routes=routes)
    logger.info(f"Created Starlette SSE transport app with routes: /sse/ (GET), {message_post_path} (POST)")
    return sse_app 