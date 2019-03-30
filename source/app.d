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

void read(File file, AnsiColor color, string filename)
{
    // dfmt off
    file
        .byLineCopy
        .each!(line => ownerTid().send(color,
                                       filename,
                                       Clock.currTime.toISOExtString,
                                       line));
    // dfmt on
}

void readFile(AnsiColor color, string filename)
{
    File(filename).read(color, filename);
}

void readProcess(AnsiColor color, string command)
{
    auto pipes = pipeShell(command, Redirect.stdout | Redirect.stderrToStdout);
    pipes.stdout.read(color, command);
    auto res = pipes.pid.wait;
    enforce(res == 0, "Command execution for %s failed with %s".format(command, res));
}

struct Failed
{
    string why;
}

void readCommand(string command)
{
    auto r = regex("(?P<protocol>.*?)://(?P<color>.*?)/(?P<rest>.*)");
    auto m = command.matchFirst(r);
    enforce(m, "Cannot parse " ~ command);

    auto protocol = m["protocol"];
    auto color = to!AnsiColor(m["color"]);
    auto rest = m["rest"];
    switch (m["protocol"])
    {
    case "file":
        readFile(color, rest);
        break;
    case "process":
        readProcess(color, rest);
        break;
    default:
        throw new Exception("Cannot work with " ~ command);
    }
}

void noThrowReadCommand(string command) {
    try
        readCommand(command);
    catch (Exception e)
        ownerTid().send(Failed(e.message.idup));
}

void main(string[] args)
{
    auto subprocesses = args[1 .. $].map!(command => spawnLinked(&noThrowReadCommand, command)).array.count;
    while (subprocesses > 0)
    {
        // dfmt off
        receive(
            (AnsiColor color, string channel, string timestamp, string message)
            {
                writeln(new StyledString("%-26s %s: %s".format(timestamp, channel, message)).setForeground(color));
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
