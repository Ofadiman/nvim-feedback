# Answer template

```markdown
### `src/report/parse.py:42-47`

> Why does this loop start at index 1?

Row 0 is the header. `read_header` consumes it at `src/report/parse.py:31` and stores the column names, so the loop starts at the first data row. Starting at 0 would pass the header to the numeric check at `src/report/parse.py:45`, which rejects it.
```

- The heading is the location where you found the item: `<file>:<start_line>-<end_line>`, or `<file>:<line>` for a single line.
- The quote is the comment verbatim, with every line prefixed by `> `.
- The answer opens with the direct answer, then gives the evidence, citing `file:line` for each claim about the code.
