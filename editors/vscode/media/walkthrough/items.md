# Items are paragraphs

An item is a paragraph or list entry of a Markdown document that starts with a marker:

```markdown
%req[login.lockout] After five failed sign-ins, the account shall be locked for 15 minutes.

%test[t.lockout verifies=login.lockout] Five bad passwords, then a good one: refused.
```

`%[login.lockout]` anywhere refers to the item. As you type, the editor completes types, IDs, statuses and link types, and the Problems panel shows what `skein check` reports, with quick fixes.
