# Report template

## Change entry

```markdown
### `src/report/parse.py:52-58`

> Skip blank rows instead of raising on them.

`parse_rows` now skips a row whose cells are all empty before the numeric check (`src/report/parse.py:53`), and `test_parse_rows_skips_blank_rows` covers it (`tests/test_parse.py:88`). `pytest tests/test_parse.py` passes.
```

## Answer

```markdown
### `src/report/parse.py:42-47`

> Why does this loop start at index 1?

Row 0 is the header. `read_header` consumes it at `src/report/parse.py:31` and stores the column names, so the loop starts at the first data row. Starting at 0 would pass the header to the numeric check at `src/report/parse.py:45`, which rejects it.
```

## Rules

- The heading is the location where you found the item: `<file>:<start_line>-<end_line>`, or `<file>:<line>` for a single line.
- The quote is the comment verbatim, with every line prefixed by `> `.
- A change entry says what you changed, citing `file:line` for each change, and names the check that verified it. When the code already satisfied the comment, the entry says so and gives the evidence.
- An answer opens with the direct answer, then gives the evidence, citing `file:line` for each claim about the code.
