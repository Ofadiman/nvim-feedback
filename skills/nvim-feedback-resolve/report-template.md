# Report template

## Change entry

````markdown
### `src/report/parse.py:52-56`

```python
def parse_rows(rows):
    parsed = []
    for row in rows:
        parsed.append([float(cell) for cell in row])
    return parsed
```

> Skip blank rows instead of raising on them.

`parse_rows` now skips a row whose cells are all empty before the numeric check (`src/report/parse.py:55`), and `test_parse_rows_skips_blank_rows` covers it (`tests/test_parse.py:88`). `pytest tests/test_parse.py` passes.
````

## Answer

````markdown
### `src/report/parse.py:42-47`

```python
for index in range(1, len(rows)):
    row = rows[index]
    if len(row) != len(names):
        raise ValueError(f"row {index} has {len(row)} cells")
    values = [float(cell) for cell in row]
    records.append(dict(zip(names, values)))
```

> Why does this loop start at index 1?

Row 0 is the header. `read_header` consumes it at `src/report/parse.py:31` and stores the column names, so the loop starts at the first data row. Starting at 0 would pass the header to the numeric check at `src/report/parse.py:46`, which rejects it.
````

## Rules

- The heading is the location where you found the item: `<file>:<start_line>-<end_line>`, or `<file>:<line>` for a single line.
- Below the heading, a fenced code block tagged with the file's language shows the code the comment targets: `anchor.selected_lines` for a linewise item, `anchor.selected_text` for a characterwise item, and the `anchor.selected_block` entries, one per line, for a blockwise item. The fence is longer than any run of backticks in the code.
- The quote is the comment verbatim, with every line prefixed by `> `.
- A change entry says what you changed, citing `file:line` for each change, and names the check that verified it. When the code already satisfied the comment, the entry says so and gives the evidence.
- An answer opens with the direct answer, then gives the evidence, citing `file:line` for each claim about the code.
