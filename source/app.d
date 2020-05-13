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
        .filter!(line => line.length > 0)
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
void readSerial(string serialSettings, string channel, AnsiColor color)
{
    auto r = regex("(?P<path>.+?):(?P<baudrate>.*)");
    auto m = serialSettings.matchFirst(r);
    enforce(m, "Cannot parse " ~ serialSettings);

    auto path = m["path"];
    auto baudrate = m["baudrate"];
    auto file = File(path);
    file.setBaudrate(baudrate.to!int);
    file.read(channel, color);
}

// name:color=[file:path|process:cmd|serial:path:baudrate]
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
    case "serial":
        rest.readSerial(channel, color);
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
    import std.getopt;

    auto helpInformation = getopt(args, std.getopt.config.passThrough);
    if (helpInformation.helpWanted)
    {
        defaultGetoptPrinter("Usage: pcat (id:color=protocol:rest)+\n  protocol = file|process|serial\n  file = file:path\n  process = process:command\n  serial = serial:path:baudrate",
                helpInformation.options);
        return;
    }

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
