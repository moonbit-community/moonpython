# A small "real-world"-ish script that stays within the supported subset.


def add_task(tasks, title):
    return tasks + [title]


tasks = ["write docs", "ship build"]
tasks = add_task(tasks, "celebrate")

print(f"tasks: {', '.join(tasks)}")

squares = [x * x for x in range(8)]
print("squares:", squares)

pairs = [(x, x + 1) for x in range(3)]
print("pairs:", pairs)
