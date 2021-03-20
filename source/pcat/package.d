module pcat;

import std.range;

template foldWithHasNext(alias fun)
{

    //    [1] -> geht nicht
    //    [1,2] -> f(1, 2, false)
    //    [1,2,3] -> f(1,2,true), f(2,3,false)
    auto foldWithHasNext(Range)(Range r)
    {
        alias E = ElementType!(Range);
        struct Result
        {
            Range range;
            E current;
            E newCurrent;
            E next;
            bool hasData = true;
            this(Range r)
            {
                range = r;
                current = range.front;
                range.popFront;
                next = range.front;
                range.popFront;
            }

            @property bool empty()
            {
                return range.empty && !hasData;
            }

            @property auto front()
            {
                newCurrent = fun(current, next, !range.empty);
                return newCurrent;
            }

            void popFront()
            {
                if (range.empty)
                {
                    hasData = false;
                }
                else
                {
                    current = newCurrent;
                    next = range.front;
                    range.popFront;
                }
            }
        }

        return Result(r);
    }
}

@("foldWithHasNext") unittest
{
    import unit_threaded;
    import std;

    int context = 0;
    alias testf = (int acc, int i, bool hasNext) { return i; };
    auto test1 = foldWithHasNext!(testf)([1, 2]);
    test1.empty.shouldBeFalse;
    writeln(test1.front);
    test1.popFront;
    test1.empty.shouldBeTrue;

    auto test2 = foldWithHasNext!(testf)([1, 2, 3]);
    test2.empty.shouldBeFalse;
    writeln(test2.front);
    test2.popFront;
    test2.empty.shouldBeFalse;
    writeln(test2.front);
    test2.popFront;
    test2.empty.shouldBeTrue;
}
