// A C doorway to Stockfish for Swift. The engine runs its own UCI loop on a
// thread of its own; commands go in as text lines and answers come back as
// text lines, exactly as over a pipe, but inside the process.
#ifndef CHESSDESK_STOCKFISH_BRIDGE_H
#define CHESSDESK_STOCKFISH_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

/// Called on the engine's threads for every line the engine prints.
typedef void (*sf_line_callback)(const char* line, void* context);

/// Starts the engine once per process. Later calls are ignored.
void sf_start(sf_line_callback callback, void* context);

/// Queues one UCI command (without the newline).
void sf_send(const char* command);

#ifdef __cplusplus
}
#endif

#endif
