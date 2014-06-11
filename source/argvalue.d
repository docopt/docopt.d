import std.stdio;
import std.string;
import std.container;
import std.conv;


class ArgValue
{
    private string[] _value;

    @property {
        string[] value() {
            return _value;
        }
    }

    public this(in string obj) {
        _value = [obj.dup];
    }

    public this(in string[] obj) {
        _value = obj.dup;
    }

    public this() {
        _value = [];
    }

    override bool opEquals(Object rhs) {
       return (this.toString() == rhs.toString());
    }

    override size_t toHash() {
        return typeid(this).getHash(&this);
    }

    const ArgValue dup() {
        return new ArgValue(_value);
    }

    bool isNullOrEmpty() {
        return (_value is null || _value.length==0);
    }

    bool isFalse() {
        if (_value.length == 1) {
            return (toLower(value[0]) == "false");
        }
        return false;
    }

    bool isTrue() {
        if (_value.length == 1) {
            return (toLower(value[0]) == "true");
        }
        return false;
    }

    bool isInt() {
        if (_value.length == 1) {
            try {
                auto temp = _value[0];
                auto f = parse!int(temp);
                return true;
            } catch (ConvException e) {
                return false;
            }
        }
        return false;
    }

    int asInt() {
        if (this.isInt) {
            try {
                auto temp = _value[0];
                return parse!int(temp);
            } catch (ConvException) {
                return false;
            }
        }
        return false;
    }

    bool isString() {
        return (_value.length == 1);
    }

    bool isList() {
        return (_value.length > 1);
    }

    override string toString() {
        if (_value.length > 1) {
            string[] res;
            foreach(v; _value) {
                res ~= format("[%s]", v);
            }
            return join(res, ", ");
        } else if (_value.length == 1) {
            return _value[0];
        } else {
            return "";
        }
    }

    void add(string increment) {
        _value ~= increment.dup;
    }

    void add(string[] increment) {
        _value ~= increment.dup;
    }

    void add(int increment) {
        if (isInt()) {
            int v = asInt() + increment;
            _value[0] = format("%d", v);
        }
    }
}

unittest {
    ArgValue i = new ArgValue("3");

    assert(i.isString);
    assert(i.isList == false);
    assert(i.isTrue == false);
    assert(i.isFalse == false);
    assert(i.isInt);
    assert(i.asInt == 3);
    i.add(1);
    assert(i.asInt == 4);

    ArgValue b = new ArgValue("true");
    assert(b.isTrue);

    ArgValue b2 = new ArgValue("false");
    assert(b2.isFalse);

    ArgValue s = new ArgValue("hello");
    assert(s.isString);
    assert(s.isList == false);

    s.add("world");
    assert(s.toString == "[hello], [world]");
}
