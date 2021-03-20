import colored;
import std.algorithm;
import std.concurrency;
import std.conv;
import std.datetime;
import std.exception;
import std.process;
import std.range;
import std.regex;
import std.stdio;
import std.string;

enum Mode
{
    absolute,
    relative
}

void read(File file, Mode mode, string channel, AnsiColor color)
{
    // dfmt off
    auto filtered = file
        .byLineCopy
        .filter!(line => line.length > 0)
        .chain(["TheSentinel"]);
    // dfmt on

    if (mode == Mode.relative)
    {
        struct Line
        {
            string text;
            SysTime timestamp;
        }

        auto f = (AnsiColor color, string channel, Line line, Line nextLine) {
            ownerTid().send(color, channel, line.timestamp, line.text,
                    nextLine.timestamp - line.timestamp);
            return nextLine;
        };
        // dfmt off
        filtered
            .map!(line => Line(line, Clock.currTime))
            .fold!((line, nextLine) => f(color, channel, line, nextLine))
        ;
        // dfmt on
    }
    else
    {
        // dfmt off
        filtered
            .each!(line =>
                   ownerTid().send(color,
                                   channel,
                                   Clock.currTime.toISOExtString,
                                   line))
        ;
        // dfmt on
    }
}

void readFile(string filename, Mode mode, string channel, AnsiColor color)
{
    File(filename).read(mode, channel, color);
}

void readProcess(string command, Mode mode, string channel, AnsiColor color)
{
    auto pipes = command.pipeShell(Redirect.stdout | Redirect.stderrToStdout);
    pipes.stdout.read(mode, channel, color);
    auto res = pipes.pid.wait;
    enforce(res == 0, "Command execution for %s failed with %s".format(command, res));
}

version (linux)
{
    File setBaudrate(File file, int baudrate)
    {
        import core.sys.posix.sys.ioctl;

        termios2 options;
        auto res = ioctl(file.fileno, TCGETS2, &options);
        enforce(res == 0, "Cannot TCGETS2");

        enum CBAUD = std.conv.octal!10007;
        enum CBOTHER = std.conv.octal!10000;
        options.c_cflag &= ~CBAUD; //Remove current BAUD rate
        options.c_cflag |= CBOTHER; //Allow custom BAUD rate using int input
        options.c_ispeed = baudrate; //Set the input BAUD rate
        options.c_ospeed = baudrate; //Set the output BAUD rate
        res = ioctl(file.fileno, _IOW!termios2('T', 0x2B), &options);
        enforce(res == 0, "Cannot TCSETS2");

        return file;
    }

    // serial:/dev/ttyUSB0:921600
    void readSerial(string serialSettings, Mode mode, string channel, AnsiColor color)
    {
        auto r = regex("(?P<path>.+?):(?P<baudrate>.*)");
        auto m = serialSettings.matchFirst(r);
        enforce(m, "Cannot parse " ~ serialSettings);

        auto path = m["path"];
        auto baudrate = m["baudrate"];
        auto file = File(path);
        file.setBaudrate(baudrate.to!int);
        file.read(mode, channel, color);
    }
}
// name:color=[file:path|process:cmd|serial:path:baudrate]
void readCommand(Mode mode, string command)
{
    auto r = regex("(?P<channel>.*?):(?P<color>.*?)=(?P<protocol>.*?):(?P<rest>.*)");
    auto m = command.matchFirst(r);
    enforce(m, "Cannot parse " ~ command);

    auto channel = m["channel"];
    auto color = to!AnsiColor(m["color"]);
    auto protocol = m["protocol"];
    auto rest = m["rest"];
    switch (m["protocol"])
    {
    case "file":
        rest.readFile(mode, channel, color);
        break;
    case "process":
        rest.readProcess(mode, channel, color);
        break;
        version (linux)
        {
    case "serial":
            rest.readSerial(mode, channel, color);
            break;
        }
    default:
        throw new Exception("Cannot work with " ~ command);
    }
}

struct Failed
{
    string why;
}

void noThrowReadCommand(Mode mode, string command)
{
    try
        readCommand(mode, command);
    catch (Exception e)
        ownerTid.send(Failed(e.message.idup));
}

import std.getopt;

void main(string[] args)
{
    Mode mode;
    auto helpInformation = getopt(args, "mode|m", &mode, std.getopt.config.passThrough);
    if (helpInformation.helpWanted)
    {
        auto protocol = "file|process";
        version (linux)
        {
            protocol ~= "|serial";
        }
        defaultGetoptPrinter("Usage: pcat [--mode] [--help] (id:color=protocol:rest)+\n  protocol = " ~ protocol
                ~ "\n  file = file:path\n  process = process:command\n  serial = serial:path:baudrate",
                helpInformation.options);
        return;
    }

    // dfmt off
    auto subprocesses = args[1 .. $]
        .map!(command => (&noThrowReadCommand).spawnLinked(mode, command))
        .array
        .count;
    // dfmt on
    while (subprocesses > 0)
    {
        // dfmt off
        receive(
            (AnsiColor color, string channel, string timestamp, string message)
            {
                // absolute mode
                writeln(new StyledString("%s %s ".format(timestamp.padRight('0', 27), channel)).setForeground(color), message);
            },
            (AnsiColor color, string channel, SysTime startTime, string message, Duration duration)
            {
                // relative mode
                writeln(new StyledString("%s %s %s ".format(startTime.to!string.padRight('0', 27), duration.total!"seconds", channel)).setForeground(color), message);
            },
            (LinkTerminated terminated)
            {
                subprocesses--;
            },
            (Failed error)
            {
                throw new Exception(error.why);
            },
        );
        // dfmt on
    }
}
