## Summary

<!-- What does this pull request change, and why? -->

## Related issue

<!-- For example: Fixes #123. Write "None" if there isn't one. -->

## How you tested

- [ ] Windows PowerShell tests, in Windows PowerShell 5.1
- [ ] Build tests, in PowerShell 7
- [ ] Vanta Manager tests (`cargo test --locked` in `app/`)
- [ ] Built the Vanta package and verified it with `tools/build/Test-Package.ps1`
- [ ] Installed Vanta on a VM (needed for changes to what Vanta does to a PC)

<!-- Add anything else you checked, such as the steps you followed on the VM. -->

## Checklist

- [ ] After changing tweak or toggle definitions, I ran the generators, then ran them with `-Validate`
- [ ] I updated the documentation for any behaviour I changed
- [ ] Scripts under `package/` use Windows PowerShell 5.1 syntax
- [ ] My changes follow the writing style guide

See Contributing in the Vanta documentation and the contributing guide for details.
