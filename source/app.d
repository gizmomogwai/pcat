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

void read(File file, string channel, AnsiColor color)
{
    // dfmt off
    file
        .byLineCopy
        .each!(line =>
               ownerTid().send(color,
                               channel,
                               Clock.currTime.toISOExtString,
                               line));
    // dfmt on
}

void readFile(string filename, string channel, AnsiColor color)
{
    File(filename).read(channel, color);
}

void readProcess(string command, string channel, AnsiColor color)
{
    auto pipes = command.pipeShell(Redirect.stdout | Redirect.stderrToStdout);
    pipes.stdout.read(channel, color);
    auto res = pipes.pid.wait;
    enforce(res == 0, "Command execution for %s failed with %s".format(command, res));
}

void readCommand(string command)
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
        rest.readFile(channel, color);
        break;
    case "process":
        rest.readProcess(channel, color);
        break;
    default:
        throw new Exception("Cannot work with " ~ command);
    }
}

struct Failed
{
    string why;
}

void noThrowReadCommand(string command)
{
    try
        readCommand(command);
    catch (Exception e)
        ownerTid.send(Failed(e.message.idup));
}

void main(string[] args)
{
    // dfmt off
    auto subprocesses = args[1 .. $]
        .map!(command => (&noThrowReadCommand).spawnLinked(command))
        .array
        .count;
    // dfmt on
    while (subprocesses > 0)
    {
        // dfmt off
        receive(
            (AnsiColor color, string channel, string timestamp, string message)
            {
                writeln(new StyledString("%-26s %s ".format(timestamp, channel)).setForeground(color), message);
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
