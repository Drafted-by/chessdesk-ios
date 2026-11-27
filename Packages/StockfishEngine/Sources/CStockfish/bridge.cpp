// ChessDesk's in-process bridge to Stockfish. Stockfish reads std::cin and
// writes std::cout; here both are pointed at in-memory buffers, so the engine
// is driven with UCI text without a pipe or a second process (iOS has none).
// This file is part of the app's GPL-3.0 combined work with Stockfish.

#include "include/stockfish_bridge.h"

#include <condition_variable>
#include <deque>
#include <iostream>
#include <memory>
#include <mutex>
#include <streambuf>
#include <string>
#include <thread>
#include <utility>

#include "attacks.h"
#include "misc.h"
#include "position.h"
#include "tune.h"
#include "uci.h"

namespace {

// Lines waiting to be read by the engine's UCI loop.
class CommandBuffer: public std::streambuf {
   public:
    void push(const std::string& line) {
        {
            std::lock_guard<std::mutex> lock(mutex);
            pending.push_back(line + "\n");
        }
        ready.notify_one();
    }

   protected:
    int_type underflow() override {
        std::unique_lock<std::mutex> lock(mutex);
        ready.wait(lock, [this] { return !pending.empty(); });
        current = std::move(pending.front());
        pending.pop_front();
        setg(current.data(), current.data(), current.data() + current.size());
        return traits_type::to_int_type(*gptr());
    }

   private:
    std::mutex              mutex;
    std::condition_variable ready;
    std::deque<std::string> pending;
    std::string             current;
};

// Collects what the engine prints and hands it over line by line. Stockfish
// serialises its own output (sync_cout), so lines arrive whole.
class LineBuffer: public std::streambuf {
   public:
    sf_line_callback callback = nullptr;
    void*            context  = nullptr;

   protected:
    int_type overflow(int_type ch) override {
        if (traits_type::eq_int_type(ch, traits_type::eof()))
            return traits_type::not_eof(ch);
        std::lock_guard<std::mutex> lock(mutex);
        if (traits_type::to_char_type(ch) == '\n')
            flushLine();
        else
            line.push_back(traits_type::to_char_type(ch));
        return ch;
    }

    std::streamsize xsputn(const char* text, std::streamsize count) override {
        std::lock_guard<std::mutex> lock(mutex);
        for (std::streamsize i = 0; i < count; ++i)
        {
            if (text[i] == '\n')
                flushLine();
            else
                line.push_back(text[i]);
        }
        return count;
    }

   private:
    void flushLine() {
        if (callback && !line.empty())
            callback(line.c_str(), context);
        line.clear();
    }

    std::mutex  mutex;
    std::string line;
};

CommandBuffer  commands;
LineBuffer     output;
std::once_flag started;

void run() {
    using namespace Stockfish;

    Attacks::init();
    Position::init();

    char  name[]  = "stockfish";
    char* argv[]  = {name, nullptr};
    auto  cli     = CommandLine(1, argv);
    auto  engine  = std::make_unique<UCIEngine>(std::move(cli));

    Tune::init(engine->engine_options());
    engine->loop();
}

}  // namespace

void sf_start(sf_line_callback callback, void* context) {
    std::call_once(started, [=] {
        output.callback = callback;
        output.context  = context;
        std::cin.rdbuf(&commands);
        std::cout.rdbuf(&output);
        std::thread(run).detach();
    });
}

void sf_send(const char* command) { commands.push(command); }
