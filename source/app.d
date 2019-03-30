import colored;
import std.algorithm;
import std.concurrency;
import std.datetime;
import std.stdio;

void read(string fileName, AnsiColor color)
{
    // dfmt off
    File(fileName)
        .byLineCopy
        .each!(line => ownerTid().send(color,
                                       fileName,
                                       Clock.currTime.toISOExtString,
                                       line));
    // dfmt on
}

void main(string[] args)
{
    enum colors = [
            AnsiColor.red, AnsiColor.green, AnsiColor.blue, AnsiColor.yellow,
            AnsiColor.cyan, AnsiColor.magenta
        ];
    args[1 .. $].each!((i, fileName) => spawnLinked(&read, fileName, colors[i % colors.length]));
    auto h = args.length - 1;
    while (h > 0)
    {
        // dfmt off
        receive(
            (AnsiColor color, string channel, string timestamp, string message)
            {
                writeln(new StyledString("%-26s %s: %s".format(timestamp, channel, message)).setForeground(color));
            },
            (LinkTerminated terminated)
            {
                h--;
            },
        );
        // dfmt on
    }
}
