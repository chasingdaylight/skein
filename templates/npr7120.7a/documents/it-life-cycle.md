+++
document = "IT-LIFECYCLE"
revision = "Draft"
+++

# IT life cycle: reviews and the products filed for them

The IT project life cycle has phases from Pre-Formulation to Decommission, and a key decision point (KDP) or systems engineering (SE) review at the end of each (%[IT-5.4.e]); a service line has Formulation and Implementation/Operations, with KDP-1 and KDP-2-n (%[IT-4.3]). Each is an item of the type `it-review` (`ITR-001` and on) with its kind and date, a milestone of the schedule.

%it-review[ITR-001 kind=SRR status=planned date=2027-03-01 authority="SE DA"] The System Requirements Review. (An example: replace it.)

```skein
list it-review columns=kind,status,date,authority
```

## Products

For each review the success criteria list the documents to file in the records repository the Agency CIO can reach, as preliminary, final or updated (%[IT-5.4.2.1.c] for the SRR, %[IT-5.4.2.2.f] for the PDR, %[IT-5.4.3.1.c] for the CDR, %[IT-5.4.3.2.c] for the TRR, %[IT-5.4.3.3.c] for the ORR). A product is an item of the type `it-product` (`ITP-001` and on), linked by `filed-for` to its review.

%it-product[ITP-001 state=preliminary status=planned filed-for=ITR-001] The Preliminary Project Plan, for the SRR. (An example: replace it.)

```skein
list it-product columns=state,status,filed_in
```
