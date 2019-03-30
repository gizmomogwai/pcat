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
        .each!(line =>
               ownerTid().send(color,
                               filename,
                               Clock.currTime.toISOExtString,
                               line));
    // dfmt on
}

void readFile(string filename, AnsiColor color)
{
    File(filename).read(color, filename);
}

void readProcess(string command, AnsiColor color)
{
    auto pipes = command.pipeShell(Redirect.stdout | Redirect.stderrToStdout);
    pipes.stdout.read(color, command);
    auto res = pipes.pid.wait;
    enforce(res == 0, "Command execution for %s failed with %s".format(command, res));
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
        rest.readFile(color);
        break;
    case "process":
        rest.readProcess(color);
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
