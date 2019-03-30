import colored;
import std.algorithm;
import std.concurrency;
import std.datetime;
import std.stdio;
import std.range;

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

auto advance(R)(ref R r)
{
    auto res = r.front;
    r.popFront;
    return res;
}

void main(string[] args)
{
    auto colors = cycle([AnsiColor.red, AnsiColor.green, AnsiColor.blue,
            AnsiColor.yellow, AnsiColor.cyan, AnsiColor.magenta]);
    args[1 .. $].each!(fileName => spawnLinked(&read, fileName, advance(colors)));
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
