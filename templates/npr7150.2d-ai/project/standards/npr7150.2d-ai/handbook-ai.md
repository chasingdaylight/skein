<!-- What topics 7.25 (Artificial Intelligence And Software Engineering) and 8.25 (Artificial Intelligence And Software Assurance) of the NASA Software Engineering Handbook (Version D) say bears on the requirements of NPR 7150.2D, in skein's words and with "AI" throughout, from the Internet Archive's copy of swehb.nasa.gov of 2026-10-09, read 2026-11-22. The requirements they name are the ones linked; the sections are the topics' own. Maintained by hand from here when NASA revises the topics. -->

# The handbook on AI

Each note says what a topic of the handbook asks of a requirement of the NPR when the software uses AI or machine learning (ML). Topic 7.25 adds that all of the NPR's requirements apply to AI software as to any other, and that its software development plan and software requirements have to say how AI is managed: its data, its models, performance, uncertainty, accuracy and redundancy.

## Topic 7.25: engineering

%ai-note[AIN-001 topic=7.25 section=7.2 bears-on=SWE-033] The assessment of acquisition against development covers AI too: whether to use AI or ML at all, and whether to take an open source or off-the-shelf model or build one.

%ai-note[AIN-002 topic=7.25 section=7.2 bears-on=SWE-042] NASA's electronic access to the source includes the data used to train and test the models and the resulting model, with its weights and biases.

%ai-note[AIN-003 topic=7.25 section=7.2 bears-on=SWE-219] For modified condition/decision coverage of safety-critical software, each node of a neural network is to be shown to affect the solution, and all paths evaluated.

%ai-note[AIN-004 topic=7.25 section=7.2 bears-on=SWE-146] AI and ML are a means of generating software, so the requirement applies to AI algorithms, their data files, their model files and any source code AI generates. For code AI generates, the developer stays responsible for it and reviews it before submitting it (section 6).

%ai-note[AIN-005 topic=7.25 section=7.2 bears-on=SWE-206] Access to the inputs of generation is emphasized for AI and ML and for the data files.

%ai-note[AIN-006 topic=7.25 section=7.2 bears-on=SWE-055] Validation of an AI or ML system uses data beyond the data used to train and to test the model.

%ai-note[AIN-007 topic=7.25 section=7.2 bears-on=SWE-196] The data files used to train, test or modify a model are kept and archived with the model.

%ai-note[AIN-008 topic=7.25 section=7.2 bears-on=SWE-057] The architecture shows the neural network model and where the data is routed through the system, and describes the AI or ML system clearly.

%ai-note[AIN-009 topic=7.25 section=7.2 bears-on=SWE-058] The design shows the number of nodes, the feedback loops of reinforcement learning, where each set of data goes in and out, the bias information, the weights or coefficients of the nodes, and the other design considerations.

%ai-note[AIN-010 topic=7.25 section=4.5 bears-on=SWE-156,SWE-211] The data and the model need to be secure and safe: a data set that was not examined is an attack vector, AI libraries have vulnerabilities, and most AI packages are off-the-shelf code whose limits are to be understood and tested. In critical systems the data files get the same rigor as safety-critical code.

%ai-note[AIN-011 topic=7.25 section=5 bears-on=SWE-205,SWE-066,SWE-070] The safety criticality of the software is determined with the Office of Safety and Mission Assurance, and the mission criticality of the AI algorithm is understood. Using AI or ML to generate, modify or be safety-critical code is not recommended; it supports evaluation, or acts in an advisory capacity with every output confirmed by means that do not use AI. Testing against the requirements and using validated and accredited models still apply.

%ai-note[AIN-012 topic=7.25 section=7.1 bears-on=SWE-013,SWE-050] The software plans hold the AI system's documentation, including the management of the data and the models, and the software requirements include requirements specific to the AI system: performance, uncertainty, accuracy and redundancy.

## Topic 8.25: assurance

%ai-note[AIN-013 topic=8.25 section=6.1 bears-on=SWE-066,SWE-068,SWE-193] Evaluation is a first-class activity: plans with success criteria, curated benchmarks, probabilistic acceptance thresholds and human judgment for ambiguous tasks before deployment; lightweight monitoring, failure detection, alerting and regression tracking in production; evaluation data, metrics and results under version control.

%ai-note[AIN-014 topic=8.25 section=6.2 bears-on=SWE-070] The data behind an AI system (training, fine-tuning, retrieval, prompt examples, guardrails, evaluation) has documented provenance, licensing and representativeness and is under configuration management; drift in data and in concepts is detected against thresholds with retraining or refresh criteria; synthetic data is validated and its limits documented.

%ai-note[AIN-015 topic=8.25 section=6.3 bears-on=SWE-156] Security covers the AI supply chain (provenance of models and components, signed artifacts, audited dependencies, incident response for a compromised component), the risks of generative AI such as prompt injection and excessive agency with guardrails and filtering, and red-teaming with threat modeling, its findings tracked to closure.

%ai-note[AIN-016 topic=8.25 section=6.4 bears-on=SWE-066,SWE-068,SWE-193,SWE-205] Safety engineering produces an AI safety case (hazards, mitigations, operating conditions, residual risk) reviewed at the key decision points, with runtime safety monitoring and circuit breakers, and testing aligned with the hazard scenarios. Until agency policy changes, projects are recommended to limit AI to non-safety-critical uses unless the safety case and its risk controls are approved by the appropriate authority.

%ai-note[AIN-017 topic=8.25 section=6.5 bears-on=SWE-066,SWE-068,SWE-193] Uncertainty is quantified and communicated: confidence indicators, consistency checks, grounding in retrieved sources, abstention below a threshold, and escalation paths (candidates with confidence, human review, declining to answer); verification and validation accept probabilistic criteria.

%ai-note[AIN-018 topic=8.25 section=6.6] Human oversight is chosen by risk (in the loop, on the loop, out of the loop), with documented authority boundaries, approval gates for actions an AI agent takes, and measures of how effective the oversight is, such as override rate.

%ai-note[AIN-019 topic=8.25 section=6.7] The architecture is modular, with explicit interface contracts, model routing and version isolation so that a model or provider can be swapped, rollback procedures, and monitoring of performance, drift and safety metrics.

%ai-note[AIN-020 topic=8.25 section=6.8 bears-on=SWE-070] Models, data, prompts, retrieval configurations, guardrails, tool definitions and evaluation assets are versioned and configuration-managed, with experiment tracking, so that a model can be recreated and the reasons for configuration choices are recorded.

%ai-note[AIN-021 topic=8.25 section=6.9 bears-on=SWE-151] Cost and effort plans include continuous change: monitoring, retraining or fine-tuning, retrieval refresh, evaluation updates, provider and interface migrations, and cost observability, with retirement plans and migration triggers for models and dependencies.

%ai-note[AIN-022 topic=8.25 section=6.10 bears-on=SWE-070,SWE-156] Data quality (accuracy, completeness, consistency, timeliness, relevance, representativeness and fairness) is assured across the lifecycle, with provenance and licensing documented, data pipelines secured and configuration-controlled, retrieval quality evaluated, and edge cases analyzed for gaps and bias.

%ai-note[AIN-023 topic=8.25 section=7.0 bears-on=SWE-034] Acceptance criteria for AI software are probabilistic: thresholds with the uncertainty they carry, set before the software is accepted.

%ai-note[AIN-024 topic=8.25 section=7.0 bears-on=SWE-086] Continuous risk management includes the risks of AI that the topic lists: drift, supply chain change, bias, security and loss of oversight.
