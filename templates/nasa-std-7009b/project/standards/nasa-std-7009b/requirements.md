<!-- NASA-STD-7009B, Standard for Models and Simulations (approved 2024-03-05), chapter 4, from its PDF at https://standards.nasa.gov/standard/nasa/nasa-std-7009, extracted 2026-11-22 with skein's tools/pdf. Maintained by hand from here when NASA revises the standard. -->

# Requirements

Chapter 4 of the standard: each requirement an item (`MS-40` for `[M&S 40]`), with its rationale quoted under it; the recommendations as the standard words them.

This Standard establishes a minimum set of requirements and recommendations for M&S influencing or supporting decisions, particularly critical decisions. Decisions based entirely or partially on M&S are usually made within the context of a program or project. The risk inherent in these decisions must be anticipated and correctly estimated throughout the development and use of an M&S, including an adequate assessment of uncertainities. This Standard establishes practices to help reduce, assess, and communicate risk by making the factors supporting M&S credibility more apparent. As such, this Standard contains a number of assessments that occur during the life cycle of an M&S. This Standard provides a general M&S life cycle process, which parallels the NASA program/project management life cycle, as a basis for understanding the application of the requirements and recommendations it contains (see Appendix F, M&S Life Cycle). These requirements and recommendations emphasize the establishment, recording, and maintenance of M&S processes and products to enforce transparency, repeatability, and traceability. The language that follows in many requirements is of the form “shall maintain a record of…” the appropriate outcome, or product, of the relevant activity, to avoid multiple (three) requirements associated with the activity (one for “establishing”, one for “recording”, one for “maintaining”). However, to maintain a record of an outcome or product implies that the outcome or product be established (created). Furthermore, maintenance of the record implies that the outcome or product is re- established as a result of any changes to either the RWS or the M&S. These requirements and recommendations also encourage the appropriate training and experience base for key M&S personnel. The requirements and recommendations in this Standard are generic in nature because of their broad applicability to all types of M&S. Implementation details should be addressed in discipline- specific recommended practices, program/project/program management plans, etc. Specific requirements applicable to M&S implemented in software are found in NPR 7150.2, NASA Software Engineering Requirements. The following organizational structure is employed in this Standard:

4.1 M&S Programmatics, including:

- M&S Criticality Assessment.
- Establishment of the M&S Intended Use.
- M&S Development and Use Plans.
- Recommended Practices Identification and Use.
- Training.

4.2 M&S Development, including:

- M&S Design.
- M&S Conceptual (Design) Validation.
- M&S Verification.
- M&S Validation.
- M&S Uncertainty Characterization.
- M&S Capability Assessment.
- M&S Release.

4.3 M&S Use (Operations), including:

- M&S Use Assessment.
- M&S Setup and Execution.
- M&S Results Uncertainty Characterization.
- M&S Sensitivity Analyses.
- M&S Results Assessment.
- M&S Risk Assessment.
- M&S Results Reporting to Decision Makers.

In many instances, the modeling, simulation, and analysis activities are interwoven, particularly during the development, verification, and validation phases, but also may occur during the use (or operation) of an M&S. This Standard is inclusive of all these possibilities. Program and project management is responsible for identifying and recording the parties responsible for complying with the requirements in this Standard. The actual person identified to fulfill the role of the “responsible party” in specific requirements will likely vary depending upon the context of the requirement. For example, the responsible party might be the lead or another supporting person associated with the M&S development, operation, analysis, and/or reporting of results to decision makers. Additionally, program and project management, in collaboration with the delegated NASA Technical Authority, is responsible for establishing the extent and level of formality of processes (including any assessments) and products needed to meet the requirements in this Standard. Furthermore, the delegated NASA Technical Authority has the particular responsibility to assure appropriate outcomes of [M&S 40], [M&S 42], [M&S 43], [M&S 44], [M&S 23], [M&S 31], and [M&S 48]. The requirements that include the recording of an activity or data do not imply that either the activity in question is required or that a new record for the model, simulation, or analysis is needed. The intent is to record whether or not the activity was accomplished and the data/information resulting from its accomplishment. Also, if some evidence or artifact of the relevant activity is available, a reference to that evidence (e.g., a journal article, a technical report, an M&S development/test document or computer file, a record, an M&S user/operator guide, or a program/project document) may suffice, provided the required details are contained therein and specific locations of the required information are given. The responsible party is to incorporate M&S products, evidence, and artifacts into the project or program plans for the configuration management or technical data management processes as appropriate (see NPR 7123.1, NASA Systems Engineering Processes and Requirements). The responsible party is to provide a rationale why any requirement (or recommendation, if imposed by tailoring or direction) is not met. (See Appendices A and B.)

## 4.1 M&S Programmatics

The overarching topics of determining M&S criticality, defining basic objectives, requirements, and recommendations for M&S development and use, and understanding the results from any technical reviews performed related to the M&S are considered programmatic activities. One key task when moving toward the creation of a new M&S is defining its intended use, that is, the expected purpose and application of an M&S. This provides the initial basis of development and feeds into the concepts of “permissible use” at the end of development (see section 4.2) and “proposed use” at the beginning of M&S use (see section 4.3) in this Standard. Program and project management, in collaboration with the delegated NASA Technical Authority, has the responsibility to identify and record the critical decisions to be addressed with M&S and to determine which M&S are in scope, based upon the criticality of the situation addressed by the proposed use of the M&S. Appendix D describes a representative M&S criticality assessment matrix for this purpose.

### 4.1.1 General M&S Programmatics

%ms[MS-40 section=4.1.1.1] A record of the intended use of M&S shall be maintained.

> [Rationale: The intended use is a general statement of the aspects of an RWS included in the M&S, what the M&S does, the intended domain of validation, and a description of results expected from the M&S, and a description of the decision(s) the M&S results will inform.]

%ms[MS-06 section=4.1.1.2] A record of the assessed criticality associated with M&S use shall be maintained.

> [Rationale: The criticality assessment ensures communication of the amount of influence an M&S has on the intended use relative to the consequences of that situation.]

Appendix D describes a representative method for assessing criticality. The method used, either Appendix D as is or modified, or another method, is to be recorded. All M&S used to support critical decisions, as determined by the outcome of compliance with [M&S 6], are in scope of this Standard. Beyond that, at the discretion of program/project management and the delegated NASA Technical Authority, any other M&S may be deemed in scope of this Standard.

%ms[MS-41 section=4.1.1.3] A plan for the acquisition, development, operation, maintenance, and retirement of the M&S (including identifying the responsible organizations) shall be maintained.

> [Rationale: The M&S development and use plans are proactive bases for proceeding through the life cycle of the M&S, including when compliance with the requirements for developing and using the M&S are accomplished.]

%ms[MS-42 section=4.1.1.4] A record of the programmatic and technical metrics for the M&S shall be maintained.

> [Rationale: Defined metrics for M&S products inform developers and users as to the required data/information to collect during M&S development and use to support process improvements, assessments, or other purposes.]

Some metrics may become the basis for M&S acceptance criteria (see [M&S 43], including the associated rationale and explanatory text). Some metrics may be collected for other purposes, for example, to support M&S process improvement. Examples of programmatic metrics include, but are not limited to:

- a. Schedule progress.
- b. Cost incurred.
- c. Configuration items managed.
- d. Products delivered.

Examples of M&S technical metrics include, but are not limited to, data from/about:

- a. Verification.
- b. Validation.
- c. Uncertainty.
- d. Sensitivity analysis activities.

%ms[MS-43 section=4.1.1.5] A record of acceptance criteria for the M&S shall be maintained, including:

- a. Criteria for Verification.
- b. Criteria for Validation.
- c. Criteria for Uncertainty.
- d. Criteria for Sensitivity.
- e. M&S assessment level thresholds (for the M&S capability assessment and M&S results assessment).

> [Rationale: Defined M&S acceptance criteria provide qualitative or quantitative information with which to judge that the M&S or related products satisfy the intended use.]

M&S acceptance criteria are the bases to judge that an M&S meets its intended use (and other detailed objectives), including, but not limited to, criteria for verification, validation, uncertainty, sensitivity analysis, and assessment level thresholds. Solution accuracy and precision are part of V&V criteria. The M&S capability and M&S results assessments together establish the bases for ascertaining the credibility of the M&S results. Refer to Appendix E for definitions regarding the M&S capability assessment and M&S results assessment, as pertains to criteria relevant to [M&S 43e].

%ms[MS-44 section=4.1.1.6] A record of information unique to the M&S necessary when (relevant to) reporting results from the M&S shall be maintained (in addition to [M&S 32-39]).

> [Rationale: This requirement asks for information unique to this M&S be reported in addition to the reporting requirements of section 4.3.8 in this Standard.]

%ms[MS-09 section=4.1.1.7] A record of results of technical reviews accomplished during the life cycle of the M&S shall be maintained.

> [Rationale: Technical reviews show how and what aspects of M&S development or use were reviewed and the outcome of the reviews as support for acceptance of the M&S and the results from its use. This Standard does not require technical reviews; if they occur, the results are to be recorded and made available.]

The results from technical reviews are to include all products, as well as specific rationale, tests, and other insights attributable to the review that support traceability of the findings. Refer to NASA-HDBK-7009, NASA Handbook for Models and Simulations: An Implementation Guide for NASA-STD-7009, for more on this topic.

%ms[MS-51 section=4.1.1.8] A record of M&S defects or problems from discovery through closure shall be maintained.

> [Rationale: A record of existing defects of problems with the M&S provides necessary cautions to M&S users and recipients of M&S-based results, as well as areas for future M&S improvement.]

Defects in, or problems with, the M&S may be found during M&S development or use. This does not necessarily preclude use of the M&S, but the M&S users and recipients of M&S-based results are to be made aware of their existence and impacts on M&S risk (as part of [M&S 39]).

### 4.1.2 General M&S Programmatic Recommendations

Recommendations for general M&S practices are that responsible parties should:

- a. Record the M&S waiver processes.
- b. Record the extent to which an M&S effort exhibits the characteristics of work product management, process definition, process measurement, process control, process change, and continuous improvement, including configuration management (CM) and M&S support and maintenance.

### 4.1.3 M&S Best Practices Recommendations

This Standard addresses general issues with respect to the use of M&S and does not discuss implementation details specific to individual programs, projects, disciplines, or processes. The implementation details are addressed in relevant recommended practices (e.g., guidelines developed by professional societies, such as AIAA G-077, Guide for the Verification and Validation of Computational Fluid Dynamics Simulations, and ASME V&V 10, other best practices documented for specific simulation codes, and NASA handbooks and guidebooks. Recommendations for the identification of recommended practices by responsible parties are as follows:

- a. Identify and record the recommended practices that apply to M&S for the program/project.
- b. At a minimum, consider the recommended practices for the following areas:
  - (1) Data and M&S input verification, validation, and pedigree.
  - (2) An auditing method of tracking adherence to recommended practices.
  - (3) V&V processes for the M&S.
  - (4) Uncertainty characterization methods for the M&S.
  - (5) Sensitivity analysis methods for the M&S.
  - (6) Understanding of the disciplines incorporated in the M&S.
  - (7) Analyzing and interpreting the M&S results, including documentation of inference guidelines and statistical processes used.
  - (8) Recognizing and capturing the need for changes or improvements in the M&S.
  - (9) Reporting procedures for results.
  - (10) Best practices for user interface design to constrain the operation of the M&S to within its limits of operations.

### 4.1.4 M&S Training Recommendations

Recommendations for training by responsible parties follow:

- a. Determine the depth of required training or equivalent experience (i.e., qualifications) for developers, operators, and analysts.
- b. Record the following:
  - (1) Training topics required for developers, operators, and analysts of M&S, which should include the following:
    - A. The limits of operation for M&S, with implications and rationale.
    - B. CM requirements.
    - C. The requirements and recommendations for recording information specified in this Standard.
    - D. How to recognize unrealistic results from simulations.
    - E. Feedback processes to improve M&S processes and results, including providing feedback for results that are not credible, are unrealistic, or defy explanation.
    - F. Sensitivity analysis.
    - G. Uncertainty characterization.
    - H. V&V.
    - I. How to report simulation results to decision makers.
    - J. Statistics and probability.
    - K. Discipline-specific recommended practices. Other applicable Agency policy, procedural requirements, and standards.
    - L. Basic modeling structures, mathematics, assumptions, and abstractions.
  - (2) Process and criteria for verifying that training requirements are met.

## 4.2 M&S Development

The M&S development processes vary depending on the intended use and may be referred to as modeling activities. This phase in the M&S life cycle (see Appendix F) begins by specifying the intended use of the M&S and by establishing an understanding of the existing or envisioned system to be modeled. This is followed by developing the concept for the M&S (including conceptual, mathematical, or computational diagrams or models), continues with choosing application methods and platforms for implementing and testing (both verifying and validating) the M&S, and ends with releasing the M&S for use. The permissible uses for the M&S are determined during development with an understanding of the abstractions taken in development, the assumptions for M&S use, the constraints of implementation methods used, and the limits of operation based on the completeness and success of both V&V.

### 4.2.1 General M&S Development

%ms[MS-10 section=4.2.1.1] A record of relevant characteristics, including data, of the RWS to be modeled, including its pedigree, shall be maintained (see Data Pedigree in Appendix E).

> [Rationale: Establishing the relevant characteristics of the RWS is part of analyzing and decomposing the RWS and provides the basis for M&S design, conceptual validation, development, and use.]

RWS can be interpreted as narrowly or broadly as necessary, that is, from a single specific system to a whole class of systems, depending on the intended use of the M&S.

%ms[MS-45 section=4.2.1.2] The data sets and supporting software used in M&S development shall be maintained.

> [Rationale: The data sets and supporting software provide bases and support to M&S development, possible technical reviews, and re-creation or reproduction of the M&S, as needed.]

%ms[MS-46 section=4.2.1.3] A record of the units and vector coordinate frames for all quantities and input/output variables or parameters in the M&S shall be maintained (where applicable).

> [Rationale: M&S units and vector coordinate frames are a required part of correlating the M&S’s representation of the RWS (and are required as part of M&S V&V).]

%ms[MS-11 section=4.2.1.4] A record of the assumptions and abstractions underlying the conceptual and implemented model, including their rationales and consequences with respect to the intended uses of the M&S, shall be maintained.

> [Rationale: Making abstractions and assumptions are part of the modeling process of analyzing, decomposing, and representing an RWS. Recording the abstractions and assumptions clarifies areas where the M&S differs from the RWS or where limits of implementation mechanisms may cause the M&S’ response to differ from that of the RWS. This also provides an understanding needed for verification, validation, uncertainty characterization, the specification of permissible uses, and the acceptance of the M&S for a proposed use. Failure to clearly identify, understand, and communicate assumptions and abstractions introduces risks throughout development and use of the M&S.]

%ms[MS-12 section=4.2.1.5] A record of the concepts, structures, and mathematics of the M&S (e.g., techniques, equations solved, behaviors or states characterized, flow of execution, conceptual models) shall be maintained.

> [Rationale: The act of modeling encompasses making choices as to how best to represent the RWS or elements (components) thereof. These concepts, structures, and mathematics of the M&S provide the basis for the detailed design and specification of the M&S, which provide the basis for verification of the M&S.]

For commercial off-the-shelf (COTS), Government off-the-shelf (GOTS), modified off-the-shelf (MOTS), and legacy M&S, some of the information from [M&S 11-12] may be available in published user guides; a reference to the user guides may suffice for this part of these records.

%ms[MS-13 section=4.2.1.6] A record of the M&S limits (e.g., boundary conditions) shall be maintained.

> [Rationale: The M&S limits provide the broadest bounds for potential M&S Use that produce results, beyond which the M&S does (or will) not function (correctly).]

The M&S limits are determined by the following:

- a. The design choices in modeling (representing) the RWS.
- b. The implementation mechanisms chosen.

For comparison, see definitions of “Domain of Verification” and “Domain of Validation.”

%ms[MS-14 section=4.2.1.7] A record of the permissible uses of the M&S shall be maintained.

> [Rationale: Recording the permissible uses of an M&S at the end of M&S development aggregates the latest available information about the intended uses, limiting assumptions and abstractions, and V&V limits. The permissible uses are the basis for performing the use assessment of [M&S 23].]

When a model’s development is completed, the permissible uses are determined by the intended use [M&S 40]; the model’s assumptions and abstractions [M&S 11]; the M&S limits [M&S 13]; the domain of verification [M&S 16]; and the domain of validation [M&S 18]. Furthermore, the permissible uses are the criteria by which the proposed use is assessed [M&S 22].

%ms[MS-48 section=4.2.1.8] A record of the assessed M&S capability shall be maintained according to each of the following factors:

- a. M&S Data Pedigree.
- b. M&S Verification.
- c. M&S Validation.
- d. M&S Development Technical Review.
- e. M&S Development Process/Product Management.

> [Rationale: The assessment of each M&S capability factor ensures a discussion of the achievements and shortcomings of the M&S as developed with respect to the intended use and provides rationale for either acceptance or rejection of the M&S for release and use.]

See Appendix E for more on this topic.

%ms[MS-47 section=4.2.1.9] Guidance on how to use the M&S shall be maintained, including:

- a. Appropriate practices for:
  - (1) Setup.
  - (2) Execution.
  - (3) Interfaces with other models when the M&S is used as part of either a linked or coupled model.
  - (4) Analysis of results.
- b. Obsolescence criteria.
- c. Parameter calibrations.
- d. Computational requirements (e.g., required hardware/software versions, main memory, disk capacities, processor, and compilation options).

> [Rationale: A user's guide provides information on the appropriate application of an M&S, including M&S functions and limitations, descriptions of appropriate practices for set-up, execution, interfaces with other models when the M&S is used as part of either a linked or coupled model, and analysis of results.]

An M&S User’s Guide Outline is included as an appendix in NASA-HDBK-7009. Obsolescence refers to situations where changes to the real system invalidate the M&S. The computational requirements are for both M&S Development and M&S Use (if they are different). These requirements may be either the minimum computational requirements (operating system, hardware configuration, etc.) for the M&S or the computational configuration(s) used throughout M&S development.

### 4.2.2 General M&S Development Recommendations

Recommendations for general M&S development are that responsible parties should:

- a. Record the methods of uncertainty characterization and the uncertainty in any data used to develop the M&S or incorporated into the M&S.
- b. Proceed with development activities in a manner that reduces risk to the project and application of the M&S by limiting the definition of the modeled RWS and its environment to only include interactions relevant to the intended use of the M&S.
- c. Design and construct the M&S so that, in the event of a failure, messages detailing the failure mode and point of failure are provided. This feature helps to prevent the inappropriate use of potentially misleading results.
- d. Record updates of the M&S (e.g., solution adjustment, change of parameters, calibration, and test cases) and assign unique version identifier, description, and the justification for the updates.
- e. Include test cases in the CM records that span the M&S limits defined by the program or project. “Test cases” are defined as benchmark input/output sets used to verify proper execution of the M&S.
- f. Provide a feedback mechanism for users to report unusual results to M&S developers or maintainers.
- g. Maintain (conceptual, mathematical, and computational) models, simulations, and associated records in a controlled CM system.
- h. Maintain the data sets and supporting software referenced in [M&S 45] and the associated records in a controlled CM system.
- i. Convey serious concerns about M&S to project managers (and decision makers, if appropriate) as soon as they are known.

### 4.2.3 M&S Verification

The process of testing an M&S takes two distinct forms: V&V. While both these activities test the M&S, they do so for different reasons. Verification is testing with respect to model specification and design. V&V often occur in a cyclical or mixed manner depending on many factors in the overall M&S development process and the success or failure in the testing process.

%ms[MS-15 section=4.2.3.1] The M&S shall be verified.

%ms[MS-16 section=4.2.3.2] A record of the domain of verification of the verified M&S shall be maintained.

> [Rationale: Verifying the M&S ensures it is implemented in accordance with its design. The domain of verification for the M&S provides operational criterion for which it is known to produce results within the capabilities for which it was constructed.]

There are two distinct aspects of verification:

- a. Implementation (code) verification determines the degree to which the implemented M&S contains everything in the M&S Design (and nothing more). In the M&S life cycle, this is the first activity in the M&S Testing phase.
- b. Solution verification determines the M&S is working without errors and achieving accuracy goals. In the M&S life cycle, this takes place each time the M&S is used, either in the M&S Testing phase or M&S Use phase.

See Appendix E for more on this topic.

### 4.2.4 M&S Verification Recommendations

Recommendations for verification of M&S are that the responsible party should:

- a. Record verification techniques used. NASA-HDBK-7009 has further information regarding specific verification techniques, including the order of precedence of verification prior to validation to reduce technical and programmatic risk.
- b. Record numerical error estimates (e.g., numerical approximations, insufficient discretization, insufficient iterative convergence, finite-precision arithmetic) for the results of the computational model.
- c. Record the verification status of conceptual, mathematical, and computational models.
- d. Record aspects of M&S not verified.

### 4.2.5 M&S Validation

M&S validation is testing a model or simulation and comparing its responses or results to the system the M&S is representing or an acceptable alternative (e.g., a testbed, prototype, or similar representative system). (See discussion of verification in section 4.2.3.)

%ms[MS-17 section=4.2.5.1] The M&S shall be validated.

%ms[MS-18 section=4.2.5.2] A record of the domain of validation of the validated M&S shall be maintained.

> [Rationale: Validating the M&S ensures it produces results acceptably similar to the RWS it represents. The domain of validation for the M&S provides operational criterion for which it is known to produce results acceptably similar to the RWS it represents.]

The two distinct aspects of validation are:

- a. Conceptual (design) validation determines the degree to which a conceptual model or M&S design adequately represents the real world from the perspective of the intended uses of the M&S. In the M&S life cycle, this takes place at the end of an M&S design phase.
- b. Empirical validation determines the degree to which an operating M&S is, or provides an accurate representation of, the real world from the perspective of the intended uses of the M&S. In the M&S life cycle, this takes place during the M&S testing phase.

For each M&S validation, the source(s) of empirical data, the methods and processes used to acquire these data, and the methods and processes to manipulate these data as needed for M&S validation are to be assessed with the same level of rigor as the validation of the respective M&S. Furthermore, assessments of empirical data acquisition and processing are to include evaluation(s) to assure these data are relevant and are sufficiently accurate representations of the RWS for which the M&S is being used and data produced. Further details about the issue of proper use of empirical data for M&S validation is presented in NASA-HDBK-7009. See Appendix E for more on M&S validation.

### 4.2.6 M&S Validation Recommendations

Recommendations for validation of M&S are that the responsible party should:

- a. Record the techniques used to validate the M&S for its intended use, including the experimental design and analysis. NASA-HDBK-7009 has further information regarding specific validation techniques.
- b. Record the validation metrics, referents, and data sets used for M&S validation.
- c. Record the studies conducted, and the status and results of, M&S validation.
- d. Record the aspects of the M&S not validated.

### 4.2.7 Uncertainty Characterization in M&S Development

No M&S is a perfect replica or imitator of the RWS for which the M&S is used to study. Characterizing the uncertainty in M&S results is at least one way to qualify those results. Factors influencing that uncertainty may occur in any part of the M&S life cycle, from the initial understanding of the RWS and the earliest conceptualization of the M&S through all aspects of M&S development, testing, and use. When little actual information is available, this characterization may itself be qualitative or may be quantified if data are or become available. The requirements and recommendations in this section are related to the handling and incorporation of uncertainties during M&S development.

%ms[MS-19 section=4.2.7.1] A record of the processes and rationale for characterizing uncertainty in the referent data shall be maintained.

> [Rationale: Explaining and recording how M&S uncertainty is incorporated in, and propagated through, an M&S ensures rational consideration was given to the effects of uncertainty during M&S development.]

%ms[MS-21 section=4.2.7.2] A record of the qualitatively described or quantitative uncertainties incorporated into the M&S shall be maintained.

> [Rationale: Characterizing and recording the uncertainties in an M&S ensure an understanding of the type and magnitude of uncertainties that propagate through an M&S and affect the results.]

### 4.2.8 Uncertainty Characterization in M&S Development Recommendation

The responsible party should record significant physical processes, effects, scenarios, or environments not considered in the uncertainty characterization analysis.

## 4.3 M&S Use

The use or operation of an M&S and the processing of the results from the use are simulation and analysis activities. This phase in the life cycle (see Appendix F in this Standard) of an M&S begins with a specific use being proposed and the assessment of the proposed use against the M&S’ permissible uses. Once the use is accepted as appropriate for the M&S, the process of M&S setup and explicit scenario definition (e.g., Design of Experiments) begins, followed by the actual use (e.g., running) of the M&S, reviewing and analyzing the output results, and developing conclusions and recommendations for the RWS or situation under study.

### 4.3.1 M&S Use Requirements

%ms[MS-22 section=4.3.1.1] A record of the proposed use(s) of the M&S shall be maintained.

> [Rationale: A defined and recorded proposed use of an M&S ensures a clear communication of how the M&S is to be used, which is the subject of the use assessment required in [M&S 23].]

%ms[MS-23 section=4.3.1.2] A record of the appropriateness of the M&S relative to its proposed use(s) shall be maintained.

> [Rationale: The use assessment compares the proposed uses against the permissible uses to determine if the M&S is appropriate and if the use is within or outside the known acceptable uses of the M&S.]

Determining the appropriateness of an M&S for a proposed use, referred to as a use assessment, is obtained by comparing the proposed use [M&S 22] to the permissible use [M&S 14]. The result of the use assessment is that either the M&S is or is not accepted for the proposed use. NASA-HDBK-7009 has additional information on proposed use assessments with respect to M&S permissible uses.

%ms[MS-24 section=4.3.1.3] A record of the Input(s) to the M&S, including their pedigrees (see Input Pedigree in Appendix E of this Standard) shall be maintained.

> [Rationale: Recorded input data, including their pedigree, ensure an understanding of scenarios or experiments run with an M&S. These, coupled with associated M&S results, provide a basis for conclusions drawn from the M&S use.]

The span of inputs used for the M&S delineates the domain of M&S use, which must always be within the M&S limits; and the M&S results are best (e.g., most accurate) when M&S use takes place within the domains of V&V.

%ms[MS-25 section=4.3.1.4] A record of the processes and rationales for setting up and utilizing the M&S shall be maintained.

> [Rationale: Recorded rationale for M&S setup and execution ensures evidence is available for consideration and adjustment as needed.]

Setup and execution rationale includes any assumptions made when using the M&S.

%ms[MS-26 section=4.3.1.5] Either of the following shall be performed:

- a. Ensure M&S uses are conducted in accordance with the permissible uses and within the domains of V&V for the M&S, or
- b. Placard the M&S and analysis results with a warning that the M&S were not used in accordance with the permissible uses or were used outside the domains of V&V and include the type of limit exceeded, the extent that the limit was exceeded, and an assessment of the consequences of this action on the M&S results.

> [Rationale: Placarding M&S results if used outside established permissible uses or domains of V&V, provides a warning to the consumers of that information.]

%ms[MS-27 section=4.3.1.6] A record of the observed warning messages, error messages, and explanations for the messages resulting from the use of the M&S shall be maintained.

> [Rationale: Unexplained warning or error messages are a cause for concern (increase risk) in accepting the results of an M&S use.]

### 4.3.2 M&S Use Recommendations

Recommendations for M&S use are that responsible parties should:

- a. Record the relevant characteristics of the system that is the subject of the M&S-based analysis.
- b. Record the computational M&S used (including revision numbers) in the simulation/analysis.
- c. Record the parameter calibrations and the domain of calibration.
- d. Record the data sets and supporting software used in input preparation.
- e. Record the processes for conducting simulations and analyses for generating results reported to decision makers.
- f. Record the versions of M&S results.
- g. Record the use history of M&S, in the same or similar applications, which are relevant for assessing the capability of the current M&S application and the credibility of the results obtained from its use (see Appendix E.4.3.1 in this Standard).
- h. Record and explain all failure modes, points of failure, and messages indicating such failures.

### 4.3.3 Uncertainty Characterization in M&S Use

As mentioned in section 4.2, the characterization of uncertainty in M&S results may be influenced in any part of the M&S life cycle, including its use and the post-processing of results. The requirements and recommendations in this section are related to the incorporation, handling, and recording of uncertainties during M&S use (operations).

%ms[MS-28 section=4.3.3.1] A record of any processes and rationale for characterizing uncertainty in the following shall be maintained:

- a. The input to an M&S.
- b. The results from an M&S.
- c. The quantities derived from M&S results.

> [Rationale: Recording how and why M&S uncertainties are input to, and handled in the results of, an M&S ensures a rational basis for inclusion and analysis when an M&S is used (i.e., input and results uncertainty is not simply notional).]

%ms[MS-29 section=4.3.3.2] A record of any uncertainties (qualitatively described or quantitative) in the following shall be maintained:

- a. The input to an M&S.
- b. The results from an M&S, including MUFs incorporated into the M&S as well as factors of safety (FS) that are intended to cover uncertainties in the model or simulation.

The uncertainties those factors are intended to address should also be recorded.

- c. The quantities derived from M&S results.

> [Rationale: Characterizing the uncertainties in the input to and results from an M&S ensures an understanding of the type and magnitude of uncertainties that propagate through an M&S and show in the results.]

### 4.3.4 M&S Uncertainty Characterization in M&S Use Recommendation

Responsible parties should record significant physical processes, effects, scenarios, or environments not considered in the uncertainty characterization analysis.

### 4.3.5 M&S Sensitivity Analysis

Sensitivity analysis is the study of an M&S’ response to variations in input parameters to determine which parameters are key drivers to the M&S’s results. If the response is negligible, the M&S (at least in the experimental domain), and by inference the RWS (as validated), are considered insensitive to that parameter. Understanding the sensitivity to input parameters is key to determining the robustness of the M&S (see Results Robustness factor in Appendix E). If the response is not negligible, particularly to minor variations in the input parameters, the M&S is considered sensitive; and that parameter is a key driver to the M&S results. Assessing the similarity of M&S sensitivity with that of the RWS is one of the tasks of M&S validation with the goal that M&S and RWS sensitivities are correlated. [M&S 30] A record of the extent and results of any sensitivity analyses performed with the M&S shall be maintained.

> [Rationale: Recording the extent of sensitivity analyses ensures an understanding of how well the sensitivities were investigated and match the RWS, and provides an understanding of the stability of M&S results to input (scenario) perturbations.]

### 4.3.6 M&S Results Assessment

An established process for assessing M&S-based analysis results helps ensure clear and complete communication of the important aspects of an M&S beyond just the results. Appendix E addresses key factors that contribute to a decision-maker’s credibility assessment. The assessment of these factors is focused on the results produced by the M&S; the completeness and rigor of all the activities throughout the life cycle of the M&S contribute to it. This is why there are both developmental and operational factors for credibility. The decision makers can then interpret the M&S capability and M&S results assessments to determine the appropriate level of influence the M&S has on specific decision(s). This Standard levies no requirements with respect to what levels to achieve (the sufficiency threshold levels), merely that the levels be determined and reported.

%ms[MS-31 section=4.3.6.1] A record of the assessed M&S results shall be maintained according to each of the following factors:

- a. M&S Use Assessment.
- b. M&S Input Pedigree.
- c. M&S Uncertainty Characterization.
- d. M&S Results Robustness.
- e. M&S Use/Analysis Technical Review.
- f. M&S Use Process/Product Management.

> [Rationale: The assessment of the M&S results according to each factor ensures a discussion of the achievements and shortcomings of the M&S use beyond just the results and provides a rational basis for the appropriate interpretation/use of the M&S results with repect to the intended use.]

See Appendix E for more on this topic.

%ms[MS-49 section=4.3.6.2] A record of the assessed risks associated with the use of the M&S-based analysis shall be maintained.

> [Rationale: The assessment of the risks associated with the M&S-based analysis ensures the open communication of possible issues with the M&S results, or use thereof, and may inform program/project risk management processes.]

These risks may be due to factors inherent to the M&S, or associated with the specific application or use of the M&S. Topics in the risk assessment include, but are not limited to:

- a. The M&S criticality assessment [M&S 6].
- b. The findings from technical reviews [M&S 9].
- c. M&S defects or problems [M&S 51].
- d. Caveats [M&S 32].
- e. Uncertainty [M&S 29].
- f. Processes to obtain uncertainty [M&S 28].
- g. The M&S capability assessment [M&S 48].
- h. The M&S results assessment [M&S 31].
- i. The qualifications of developer, users, operators, or analysts.
- j. Significant differences in the M&S and their impacts from previous releases.
- k. Significant differences in M&S use and their impacts from previous uses of the same M&S release.

NASA-HDBK-7009 has additional information on risk assessments.

### 4.3.7 M&S Results Assessment Recommendations

Responsible parties should justify and record the M&S results assessment for each of the factors referenced in [M&S 31].

### 4.3.8 M&S Results Reporting

Because of the inexact nature of an M&S in replicating any given RWS, more information than just the results are needed to provide a decision maker with a more complete understanding of the situation. This includes (1) the best estimate of the results, (2) a statement on the uncertainty in the results, (3) objective, credibility supporting, assessments of the M&S capabilities and M&S results (Appendix E), (4) explicit caveats accompanying the results (e.g., the use of the M&S in violation of its assumptions or M&S limits), and (5) the risks associated with accepting the results of the M&S. This allows the decision makers to make their own conclusions about the quality or credibility of the results based upon all of this information, in the context of the decision at hand. These requirements and recommendations provide for reporting a high-level synopsis of M&S outcomes relevant to the current use.

%ms[MS-32 section=4.3.8.1] When reporting M&S results to decision makers, explicit warnings shall be included for the following occurrences, accompanied by at least a qualitative estimate of the impact of the occurrence:

- a. Unachieved acceptance criteria (as specified in [M&S 43]).
- b. Violation of assumptions of the M&S used (as specified in [M&S 11]).
- c. Violation of the M&S limits (as specified in [M&S 13]).
- d. Execution warning and error messages (see [M&S 27]).
- e. Unfavorable outcomes from the assessed appropriateness of the M&S to the proposed use (described in [M&S 23]).
- f. Issues encountered during setup and utilization of the M&S (described in [M&S 25]).
- g. Waivers to the requirements in this Standard (or the requirements specific to the M&S).
- h. Outstanding M&S defects or problems (described in [M&S 51]).

> [Rationale: Reporting warnings for negative aspects of M&S development or use helps to ensure the appropriate acceptance of M&S results, if the results are negatively impacted.]

In the absence of substantiating evidence (e.g., data, information, records) for the requirements referenced in [M&S 32 (1)-(6)], a warning is to be provided.

%ms[MS-33 section=4.3.8.2] When reporting M&S results to decision makers, an estimate of results uncertainty, as defined in [M&S 29 (1)-(3)], shall be included in one of the following ways:

- a. A quantitative estimate of the uncertainty in the M&S results, or
- b. A qualitative description of the uncertainty in the M&S results, or
- c. A clear statement that no quantitative estimate or qualitative description of uncertainty is available.

> [Rationale: Reporting an estimate of uncertainty, or lack thereof, for the M&S results ensures an understanding that the results are estimates (not exact) within assessed boundaries. Results without an estimate of uncertainty may differ vastly from those shown.]

For [M&S 33], a complete quantitative uncertainty estimate would provide uncertainty intervals about the M&S results and confidence statements based on analysis, whereas a qualitative uncertainty estimate would be provided only in linguistic terms, e.g., small, medium, or large, rather than in numeric terms. Qualitative uncertainty estimates would still require justification, for example, by the descriptive phrasing of a subject matter expert (SME) or by resort to analogy with the quantified sensitivity of similar problems.

%ms[MS-34 section=4.3.8.3] A description of the processes used to obtain the estimate of uncertainty as defined in [M&S 28 (1)-(3)] shall be included when reporting M&S results to decision makers.

> [Rationale: Reporting the processes used to obtain the estimate of uncertainty ensures the communication of how the uncertainties in the results occurred (or accumulated).]

%ms[MS-50 section=4.3.8.4] The outcome of the M&S capability assessment performed per [M&S 48] shall be included in reporting M&S results to decision makers.

> [Rationale: Reporting the M&S capability assessment ensures communication of those aspects (factors) of M&S development were accomplished, which can affect the acceptance of the M&S results.]

The “outcome” of the M&S capability assessment is understood to include the assessed levels for each capability factor specified per [M&S 48], as well as the gaps between the assessed levels and the thresholds as established per [M&S 43e]. Refer to Appendix E for additional details on this topic.

%ms[MS-35 section=4.3.8.5] The outcome of the M&S results assessment performed per [M&S 31] shall be included in reporting M&S results to decision makers.

> [Rationale: Reporting the M&S results assessment ensures communication of how well those aspects (factors) of M&S use were accomplished, which can affect the acceptance of the M&S results.]

The “outcome” of the M&S results assessment is understood to include the assessed levels for each results factor specified per [M&S 31] as well as the gaps between the assessed levels and the thresholds as established per [M&S 43e]. The assessment of M&S results is also dependent on the M&S capability, assessed in [M&S 48] and reported in [M&S 50]. Refer to Appendix E for more on this topic.

%ms[MS-36 section=4.3.8.6] The findings from technical reviews accomplished in regard to the development, management (control), and use of the M&S shall be included in reporting M&S results to decision makers.

> [Rationale: Reporting findings from any technical reviews ensures the communication of supportive or unsupportive information related to what aspects of the M&S effort were reviewed.]

Refer to NASA-HDBK-7009 for more on this topic.

%ms[MS-37 section=4.3.8.7] The qualifications of the developers of the M&S and the users, operators, or analysts involved in producing the results from the M&S, including, but not limited to, their relevant education, training, and experience, shall be included in the report of M&S results to decision makers.

> [Rationale: Reporting the qualifications of the developers, users, operators, and/or analysts involved in producing the M&S, or results therefrom, ensures clarity in qualifications. Specific topic areas that constitute qualification depends on the type and application of the M&S; the recommendations of sections 4.1.3 and 4.1.4 may be consulted.]

%ms[MS-38 section=4.3.8.8] The records of M&S development and use as shown in Appendix A shall be included in the report of M&S results to decision makers.

> [Rationale: Reporting M&S records ensures clear evidence of what was actually accomplished in M&S development and use.]

Appendix A lists all the requirements and Appendix B lists all the recommendations in a “compliance type” table with columns for applicability and rationale if not applicable. The location of applicable/required records is also necessary for compliance.

%ms[MS-39 section=4.3.8.9] The assessment of, and rationale for, acceptance of the risks associated with the results from the M&S-based analysis as determined in [M&S 49] shall be included in reporting M&S results to decision makers.

> [Rationale: Reporting assessment of and rationale for the risks associated with the use of the M&S-based analysis ensures the open communication of possible issues with the M&S, or use thereof, and may inform program/project risk management processes.]

These risks may be due to factors inherent to the M&S, or associated with the specific application or use of the M&S. Compliance with the reporting requirements [M&S 32-38, 50] yields information to inform applicable program/project risk management processes and procedures.

### 4.3.9 M&S Results Reporting Recommendations

Recommendations for reporting results from M&S use are that responsible parties should:

- a. Include concluding remarks stating whether the M&S results are credible enough for the actual use.
- b. Identify how to access more detailed backup material, including high-level descriptions of the M&S used and key assumptions for limits of validity.
- c. Place M&S results in the CM system.
- d. Summarize deviations from established recommended practices.
- e. Include dissenting technical opinions regarding the credibility of the results or any recommended actions.
- f. Convey serious concerns about M&S or its use to project managers (and decision makers, if appropriate) as soon as they are known.
