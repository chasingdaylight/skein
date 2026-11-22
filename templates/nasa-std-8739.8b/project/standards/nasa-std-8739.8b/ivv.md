<!-- NASA-STD-8739.8B, NASA Software Assurance and Software Safety Standard (approved 2022-09-08), section 4.4.2, the IV&V requirements, from its PDF at https://standards.nasa.gov/standard/NASA/NASA-STD-87398, extracted 2026-11-22 with skein's tools/pdf. Maintained by hand from here when NASA revises the standard. -->

# Independent verification and validation

The requirements of section 4.4.2 of the standard on the IV&V Provider, for projects that IV&V is performed on (NPR 7150.2D, SWE-141): each an item (`IVV-001` for 4.4.2.1).

%ivv[IVV-001 section=4.4.2.1] The IV&V Provider shall conduct planning and risk assessments to determine the specific system/software behaviors (including the software components responsible for implementing the behaviors) to be analyzed.

> Note: IV&V is a focused activity that prioritizes IV&V analysis to address the highest developmental and operational software risks. IV&V priority is based on the combination of the potential for software impacts to safety and mission success and the probability factors for latent defects. IV&V analysis activities provide coverage with a degree of rigor that reflects the priority level. The initial planning and scoping effort based on the risk assessment define the starting point for the IV&V analysis. Throughout each IV&V project, continuous and iterative feedback, through the execution of analysis, identification of issues and risks, and the collection of deeper mission understanding, allows IV&V projects to “Follow The Risk” and adjust plans. The planning and scoping effort also aid in establishing the initial relationships between the IV&V Provider, the Acquirer, and the Provider.

%ivv[IVV-002 section=4.4.2.2] The IV&V Provider shall develop and negotiate with the project an IV&V IPEP.

> Note: The IPEP documents the activities, methods, level of rigor, environments, tailoring (if any) of the IV&V requirements, and criteria to be used in performing verification and validation of in-scope system/software behaviors (including responsible software components) determined by the planning and scoping effort. A Provider should use a documented analysis approach to track and manage the IV&V effort aligned with ongoing development project efforts. The IPEP documents which software products are subject to which analyses and analysis requirements are wholly, partially, or not applied following the risk assessment and resource constraints. The IPEP also serves as a communication tool between the project and IV&V to set expectations for the IV&V products produced throughout the life-cycle. The IPEP may require updating throughout the life cycle.

%ivv[IVV-003 section=4.4.2.3] The NASA SMA Technical Authority (TA) shall review and concur with the IPEP.

%ivv[IVV-004 section=4.4.2.4] The IV&V Provider shall provide analysis results, risks, and assurance statements and data to the responsible organizations’ project management, engineering, and software assurance personnel.

> Note: While independent, the IV&V Provider is still a part of a project's overall safety and risk mitigation software assurance strategy. The results of IV&V analysis need to be incorporated into the overall software assurance assessment of the project and provided to the project management. . IV&V Provider should support project milestone reviews and provide the project with an evaluation of the lifecycle review artifacts to assist development management decisions on whether the review criteria have been met and how to proceed going forward.

%ivv[IVV-005 section=4.4.2.5] The IV&V Provider shall participate in project reviews of software activities. Participation includes providing status and results of software IV&V activities including, but not limited to, upcoming analysis activities, artifacts needed from the project, the results of the current or completed analysis, defects, and risks to stakeholders, customers, and development project personnel.

> Note: The most significant positive impact of IV&V analysis is when the analysis results are in phase with the development effort. Communicating defects after development artifacts are baselined increases the cost to make the changes. Additionally, the inclusion of the IV&V Provider in ongoing technical meetings keeps the IV&V Provider informed of possible changes that may affect future IV&V tasking. Supporting the ongoing technical meetings allows the IV&V Provider an opportunity to provide real-time feedback on these changes.

%ivv[IVV-006 section=4.4.2.6] The IV&V Provider shall provide the responsible organizations’ project management, engineering, and software assurance personnel shall insight into the software IV&V and IV&V test activities. At a minimum, the IV&V Provider will be required to allow the responsible organizations’ project management, engineering, and software assurance personnel to:

- a. Monitor the IV&V activities and plans.
- b. Review the verification activities to ensure adequacy.
- c. Review IV&V studies and source data.
- d. Audit the software IV&V processes and practices.
- e. Participate in IV&V software reviews and technical interchange meetings

%ivv[IVV-007 section=4.4.2.7] The IV&V Provider shall participate in planned software peer reviews or software inspections guided by the planning and scoping risk analysis documented in the IV&V Project Execution Plan and NASA-HDBK-2203.

> Note: The IV&V Provider should be involved in the review/inspection process for all system/software items within the scope of their analysis.

%ivv[IVV-008 section=4.4.2.8] The IV&V Provider shall establish, record, maintain, report, and utilize IV&V management and technical measurements.

> Note: The IV&V Provider gathers and analyzes metrics on a periodic basis to perform continuous improvement of IV&V processes and identify indicators of IV&V and project risks.

%ivv[IVV-009 section=4.4.2.9] The IV&V Provider shall assess and track software activities' actual results and performance against the software plans and identify and report any risks or findings to the responsible organizations’ project management, engineering, and software assurance personnel.

%ivv[IVV-010 section=4.4.2.10] The IV&V Provider shall track and evaluate changes to software products to evaluate for possible changes in the IV&V Provider’s risk analysis and potential adverse impacts to the software system and the development effort.

%ivv[IVV-011 section=4.4.2.11] The IV&V Provider shall assess the software development lifecycle for suitability for the problem to be solved and identify and communicate any risks associated with the chosen life cycle to the responsible organizations’ project management, engineering, and software assurance personnel.

%ivv[IVV-012 section=4.4.2.12] The IV&V Provider shall identify, analyze, track, communicate, and record risks to the software and development project in accordance with NPR 8000.4, Agency Risk Management Procedural Requirements to the responsible organizations’ project management, engineering, and software assurance personnel.

%ivv[IVV-013 section=4.4.2.13] The IV&V Provider shall verify the project implements the requirements for software listed in NPR 7150.2 and communicate any risks to the responsible organizations’ project management, engineering, and software assurance personnel.

%ivv[IVV-014 section=4.4.2.14] The IV&V Provider shall track, record, and communicate defects/issues and other results found during the execution of IV&V analysis and independent IV&V testing to the responsible organizations’ project management, engineering, and software assurance personnel.

%ivv[IVV-015 section=4.4.2.15] The IV&V Provider shall ensure that the identified defects and issues are addressed by the project.

%ivv[IVV-016 section=4.4.2.16] The IV&V Provider shall ensure that software planned for reuse meets the fit, form, and function as a component within the new application.

%ivv[IVV-017 section=4.4.2.17] The IV&V Provider shall ensure that the system architecture contains the computing-related items (subsystems, components, etc.) to carry out the system's mission and satisfy user needs and operational scenarios or use cases.

%ivv[IVV-018 section=4.4.2.18] The IV&V Provider shall ensure that a basis for the engineering and planning of computing-related functions is the operations, mission objectives (including mission retirement), and the system.

%ivv[IVV-019 section=4.4.2.19] The IV&V Provider shall ensure that feasibility and trade studies provide the results to confidently support the critical decisions that drove the need for the study.

%ivv[IVV-020 section=4.4.2.20] The IV&V Provider shall ensure that known software-based hazard causes, contributors, and controls are identified, documented, and trace to the project requirements.

%ivv[IVV-021 section=4.4.2.21] The IV&V Provider shall ensure that known security threats and risks are identified, appropriately documented, and updated throughout the mission lifecycle and communicated to the responsible organizations’ project management, engineering, and software assurance personnel.

%ivv[IVV-022 section=4.4.2.22] The IV&V Provider shall verify and validate that the in-scope software requirements and system requirements are, at a minimum, correct, consistent, complete, accurate, readable, traceable, and testable.

> Note: Software usually provides the interface between the user and the system hardware and the interface between system hardware components and other systems. These interfaces are critical to the successful operation and use of the system.

%ivv[IVV-023 section=4.4.2.23] The IV&V Provider shall verify and validate that the mitigations for identified security risks are in the software requirements.

> Note: Security is an essential aspect of any system development effort. In most systems, software provides the primary user interface. The user interface is an element of the system that can provide undesired access. A system concept design should address known security risks through various features in the system.

%ivv[IVV-024 section=4.4.2.24] The IV&V Provider shall ensure that software requirements meet the dependability and fault tolerance required by the system.

%ivv[IVV-025 section=4.4.2.25] The IV&V Provider shall ensure that software requirements provide the capability of controlling identified hazards and do not create hazardous conditions.

%ivv[IVV-026 section=4.4.2.26] The IV&V Provider shall verify and validate the relationship between the in-scope system/software requirements and the associated architectural elements is traceable correct, consistent, and complete.

> Note: Architectural elements are responsible for implementing specific behaviors within the software and the overall system. The interactions between these architectural elements result in the realization of the desired behaviors as well as possible undesired behaviors.

%ivv[IVV-027 section=4.4.2.27] The IV&V Provider shall verify and validate that the software architecture meets the user’s safety and mission-critical needs as defined in the requirements.

> Note: The architecture provides the foundation for the development of the software. It also significantly impacts how the software deals with faults and failures and how the software interfaces with the user and system components. Analysis of the architecture provides early insight into how the software is structured and how that structure can implement the requirements.

%ivv[IVV-028 section=4.4.2.28] The IV&V Provider shall verify and validate that the detailed design products are traceable, consistent, complete, accurate, and testable.

> Note: Detailed design is the implementation of the algorithms that control and monitor the different parts of the system and allow for interaction between the system and the user and other systems. The detailed design defines how the architectural components behave to support the interactions defined in the architecture. Analysis of the detailed design includes looking at the low-level software components in the software system.

%ivv[IVV-029 section=4.4.2.29] The IV&V Provider shall verify and validate the interfaces between the detailed design components and the hardware, users, operators, other software, and external systems are correct, consistent, complete, accurate, and testable.

> Note: While the architecture defines the interactions between the architectural elements, each element is generally composed of lower-level components defined by the detailed design. The interfaces between these components are important in ensuring that the architectural element meets its assigned responsibilities.

%ivv[IVV-030 section=4.4.2.30] The IV&V Provider shall verify and validate the relationship between the software requirements and the associated detailed design components is correct, consistent, and complete.

> Note: The detailed design components capture the approach to implementing the software requirements, including the requirements associated with fault management, security, and safety. Analysis of the relationship between the detailed design and the software requirements provides evidence that all requirements are in the detailed design.

%ivv[IVV-031 section=4.4.2.31] The IV&V Provider shall verify and validate that the software code products are consistent with architecture, complete with respect to requirements, and testable.

%ivv[IVV-032 section=4.4.2.32] The IV&V Provider shall verify and validate that the software code meets the industry best practices and software coding standards.

%ivv[IVV-033 section=4.4.2.33] The IV&V Provider shall verify and validate that the security risks in the software code are identified and mitigated.

> Note: This includes software developed by NASA, software developed for NASA, software maintained by or for NASA, COTS, GOTS, MOTS, OSS, reused software components, auto- generated code, embedded software, the software executed on processors embedded in programmable logic devices, legacy, heritage, applications, freeware, shareware, trial or demonstration software, and open-source software components.

%ivv[IVV-034 section=4.4.2.34] The IV&V Provider shall verify and validate appropriate use of off-the-shelf software, including ensuring that the project has identified all open-source software used, and that the security risks are identified and mitigated by the use of the open-source software.

%ivv[IVV-035 section=4.4.2.35] The IV&V Provider shall verify and validate that the project assesses the software systems for possible security vulnerabilities and weaknesses.

%ivv[IVV-036 section=4.4.2.36] The IV&V Provider shall verify and validate the project implements the required software security risk mitigations to ensure that security objectives for software are satisfied.

%ivv[IVV-037 section=4.4.2.37] The IV&V Provider shall verify and validate the source code through the use of analysis tools (including but not limited to static, dynamic, composition, and formal analysis tools).

> Note: The use of analysis tools may include the verification and validation of the analysis tools used by the development project in the process of developing the software. The results may be from static code analysis, software composition analysis, dynamic code analysis, cyclomatic complexity, or other code quality analysis tools.

%ivv[IVV-038 section=4.4.2.38] The IV&V Provider shall verify and validate the relationship between the software design elements and the associated software units is correct, consistent, and complete.

%ivv[IVV-039 section=4.4.2.39] The IV&V Provider shall verify and validate that the relationship between software code components and corresponding requirements is correct, complete, and consistent.

> Note: For all of the implementation requirements, it is with code that the development of software reaches its lowest level of abstraction and that the software capabilities are implemented. Evaluating the relationship between the source code and the design components and requirements provides evidence that only the specified requirements and components are in the system. Evaluating the relationship between the source code and the design components and requirements helps minimize one aspect of the emergence of unexpected behaviors: the inclusion of behaviors not specified in the requirements. The overall analysis of the code is essential in assuring that the code does implement the required software behaviors. From a safety perspective, it is important to evaluate the code and assure that known software safety and security issues such as buffer overflows and type mismatches, among many others, are not used in safety-critical aspects of the software.

%ivv[IVV-040 section=4.4.2.40] The IV&V Provider shall verify and validate that test plans, test procedures, test cases, test environment (including simulations), and test design at all levels of testing (unit, integration, system, acceptance, etc.) are correct, complete, and consistent for verification and validation of the source code and system functions allocated to the software.

%ivv[IVV-041 section=4.4.2.41] The IV&V Provider shall verify and validate that the relationships between the test plans, test procedures, test cases, test design, and source code and system functions allocated to the software are correct, complete, and consistent.

%ivv[IVV-042 section=4.4.2.42] The IV&V Provider shall verify that the test plans, test cases, test design, and test procedures contain objective acceptance criteria that support the verification of the associated requirements for both nominal and off-nominal conditions.

%ivv[IVV-043 section=4.4.2.43] The IV&V Provider shall verify that the software test results meet the associated acceptance criteria to ensure that the software correctly implements the associated requirements.

> Note: The IV&V Provider assesses the testing artifacts within the system’s meaning concerning the desired capabilities and expected operational system environment. The assessment includes an examination of testing at system boundary conditions to include unexpected conditions. The testing analysis assures that the project tests all requirements and that the system does what the requirements state it should do. The testing analysis also includes analysis of the traceability information between the tests and the requirements.

%ivv[IVV-044 section=4.4.2.44] The IV&V Provider shall verify that the project tests the required software security risk mitigations to ensure that the security objectives for the software are satisfied.

%ivv[IVV-045 section=4.4.2.45] The IV&V Provider shall verify that code coverage is measured by analysis of the results of the execution of tests.

%ivv[IVV-046 section=4.4.2.46] The IV&V Provider shall verify through independent testing each of the software requirements that trace to a hazardous event, cause, or mitigation technique.

%ivv[IVV-047 section=4.4.2.47] The IV&V Provider shall verify the project’s acceptance tests for loaded or uplinked data, rules, and code that affects software and software system behavior.

%ivv[IVV-048 section=4.4.2.48] The IV&V Provider shall participate in all NASA quality audits, assessment and reviews associated with the project.

%ivv[IVV-049 section=4.4.2.49] The IV&V Provider shall assess the software maintenance and operational risks concerning software elements to support the planning of IV&V activities during the maintenance phase. Note 1: The approach to software development on some projects results in different parts of the software going into operation at different times in the overall project life-cycle. For example, a lander mission to Mars may complete the software needed for the cruise phase to Mars while continuing to work on the entry, descent, landing, and surface operations software. Some software may also have an extended lifetime such that operational updates are anytime during the operational use of the software. Note 2: In some cases, software anomalies cause changes to the software. IV&V is important because software changes can often have ripple effects throughout the system and cause emergent behaviors. The IV&V analysis provides insight into these possible effects and provides an overall assessment of the impact of the change.
