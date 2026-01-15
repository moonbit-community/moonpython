# A small "real-world"-ish script for mpython.
#
# It intentionally exercises:
# - functions
# - lists/dicts
# - comprehensions
# - while/for, break/continue
# - match (pattern matching)
# - with (mpython's minimal implementation)
#
# It also *includes* (but does not execute) examples of:
# - classes
# - inheritance
# - operator overloading
# because those features are not fully implemented by the interpreter yet.


def add_task(tasks, title):
    # immutable style: return a new list
    return tasks + [title]


def complete_first(tasks):
    if len(tasks) == 0:
        return tasks
    # remove first element
    return tasks[1:]


def summarize(tasks):
    return f"tasks({len(tasks)}): {', '.join(tasks)}"


tasks = ["write docs", "ship build"]
tasks = add_task(tasks, "celebrate")

print(summarize(tasks))

# Control flow: while + continue + break
# We'll simulate a tiny command loop.
commands = ["add:test", "skip", "done", "add:ignored"]
idx = 0
while True:
    if idx >= len(commands):
        break

    cmd = commands[idx]
    idx = idx + 1

    if cmd == "skip":
        # demonstrate continue
        continue

    # match: parse a few command forms
    match cmd:
        case "done":
            tasks = complete_first(tasks)
        case "add:test":
            tasks = add_task(tasks, "write tests")
        case _:
            # unknown commands are ignored
            pass

print("after loop:", summarize(tasks))

# With: parsed as a statement and executed by the interpreter.
# Note: CPython expects __enter__/__exit__ for real context managers;
# mpython currently treats this as a minimal binding + block execution.
with "=>" as prefix:
    print(prefix, summarize(tasks))

# Some data crunching
squares = [x * x for x in range(8)]
print("squares:", squares)

pairs = [(x, x + 1) for x in range(3)]
print("pairs:", pairs)

# A dict comprehension (useful in real scripts)
index = {t: i for i, t in pairs}
print("index:", index)

# --- Not executed yet (future interpreter features) ---
if False:
    class Task:
        def __init__(self, title):
            self.title = title

        def __str__(self):
            return f"Task({self.title})"

        # operator overloading
        def __add__(self, other):
            return Task(self.title + "+" + other.title)

    class TimedTask(Task):
        def __init__(self, title, minutes):
            super().__init__(title)
            self.minutes = minutes

        def __str__(self):
            return f"TimedTask({self.title}, {self.minutes}m)"

    a = Task("write")
    b = Task("docs")
    print(a + b)

    t = TimedTask("ship", 15)
    print(t)

