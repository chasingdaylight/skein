+++
document = "VER"
revision = "Draft"
+++

# Verification and traceability

The verifications, each an item of the type `verification` (`VER-001` and on), of the category of its method (inspection, analysis, demonstration or test), linked by `verifies` to the requirements it shows are met; and the traces between the levels.

%verification[VER-001 test verifies=SYS-001,SRS-001] For a product with two stakeholder needs, the list shows both. (An example: replace it.)

## Business to stakeholder requirements

```skein
matrix refines
```

## Stakeholder to system requirements

```skein
matrix derives
```

## System to software requirements

```skein
matrix allocates
```

## Verification

```skein
matrix verifies
```

```skein
coverage
```
