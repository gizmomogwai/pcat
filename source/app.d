import colored;
import std;

enum Mode
{
    absolute,
    relative,
}

enum Timeunit {
    msecs,
    seconds,
    minutes,
}

void read(File file, Mode mode, string channel, AnsiColor color)
{
    // dfmt off
    auto filtered = file
        .byLineCopy
        .filter!(line => line.length > 0)
    ;
    // dfmt on

    if (mode == Mode.relative)
    {
        struct Line
        {
            string text;
            SysTime timestamp;
        }

        // dfmt off
        filtered
            .chain(["EOF"])
            .map!(line => Line(line, Clock.currTime))
            .fold!((line, nextLine) {
                ownerTid().send(color,
                                channel,
                                line.timestamp,
                                line.text,
                                nextLine.timestamp - line.timestamp);
                return nextLine;
            })
        ;
        // dfmt on
    }
    else
    {
        // dfmt off
        filtered
            .each!(line => ownerTid().send(color,
                                           channel,
                                           Clock.currTime.toISOExtString,
                                           line)
            )
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


void main(string[] args)
{
    Mode mode;
    Timeunit timeunits;

    auto helpInformation = getopt(args,
                                  "mode|m", "Timestamping mode", &mode,
                                  "timeunit|t", "Resolution of duration display", &timeunits,
                                  std.getopt.config.passThrough);
    if (helpInformation.helpWanted)
    {
        auto protocol = "file|process|serial";
        // dfmt off
        defaultGetoptPrinter("Usage: pcat [--mode=relative|absolute] [--timeunit=milliseconds|seconds|minutes] [--help] (id:color=protocol:rest)+"
                             ~ "\n  color = red|green|..."
                             ~ "\n  protocol = file|process|serial (serial only supported in linux)"
                             ~ "\n    file = file:path"
                             ~ "\n    process = process:command"
                             ~ "\n    serial = serial:path:baudrate",
                             helpInformation.options);
        // dfmt on
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
        alias pad = partial!(partial!(reverseArgs!(padRight), 27), '0');
        // dfmt off
        receive(
            (AnsiColor color, string channel, string timestamp, string message)
            {
                // absolute mode
                writeln(new StyledString("%s %s ".format(pad(timestamp), channel)).setForeground(color), message);
            },
            (AnsiColor color, string channel, SysTime startTime, string message, Duration duration)
            {
                // relative mode
                auto d = (timeunits == Timeunit.minutes) ? duration.total!"minutes" :
                    (timeunits == Timeunit.seconds) ? duration.total!"seconds" : duration.total!"msecs";
                writeln(new StyledString("%s %s %s ".format(pad(startTime.to!string), d, channel)).setForeground(color), message);
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
