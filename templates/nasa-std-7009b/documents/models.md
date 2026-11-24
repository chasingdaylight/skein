+++
document = "MS-REGISTER"
revision = "Draft"
+++

# Models and simulations

The models and simulations whose results inform the project's decisions, each an item of the type `model` (`MDL-001` and on), with its intended use (%[MS-40]) and its criticality (%[MS-06]): the consequence of the decision it informs (I negligible to V catastrophic) and its influence on it (1 negligible to 5 controlling), giving a box of the criticality matrix of Appendix D. Red ones follow the standard fully; yellow ones as program or project management and the delegated Technical Authority decide.

%model[MDL-001 consequence=III influence=4 criticality=red intended_use="Predict the peak load on the bracket during ascent"] The structural model of the bracket. (An example: replace it.)

```skein
list model columns=status,consequence,influence,criticality,intended_use
```
