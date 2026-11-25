/// Driving ports: what the presentation layer (OData, web, CLI) may ask the application to do.
module uim.myfiori.ports.usecases;

@safe:

import uim.myfiori.application.dtos;

interface IProjectUseCases {
  ProjectDto[] list();
  ProjectDto get(string id);
  ProjectDto create(CreateProjectInput input);
  ProjectDto update(string id, UpdateProjectInput input);
  /// Deletes the project including all target objects, requirements and risks.
  void remove(string id);
}

interface ITargetObjectUseCases {
  /// All target objects, optionally restricted to one project ("" = all).
  TargetObjectDto[] list(string projectId = "");
  TargetObjectDto get(string id);
  TargetObjectDto create(CreateTargetObjectInput input);
  TargetObjectDto update(string id, UpdateTargetObjectInput input);
  /// Deletes the target object including its requirements and risks.
  void remove(string id);
}

interface IRequirementUseCases {
  RequirementDto[] list(string projectId = "", string targetObjectId = "");
  RequirementDto get(string id);
  RequirementDto create(CreateRequirementInput input);
  RequirementDto update(string id, UpdateRequirementInput input);
  void remove(string id);
  /// Modellierung: applies a Kompendium module and creates all its requirements (idempotent).
  RequirementDto[] applyModule(string targetObjectId, string moduleCode);
}

interface IRiskUseCases {
  RiskDto[] list(string projectId = "", string targetObjectId = "");
  RiskDto get(string id);
  RiskDto create(CreateRiskInput input);
  RiskDto update(string id, UpdateRiskInput input);
  void remove(string id);
}

interface IReportUseCases {
  ProjectReportDto projectReport(string projectId);
  /// All data of a project for printing.
  ProjectDossierDto dossier(string projectId);
}

/// Local user accounts (login of the web GUI without XSUAA).
interface IUserUseCases {
  /// True once at least one account exists (otherwise the first admin is set up).
  bool hasUsers();
  UserDto[] list();
  UserDto get(string id);
  UserDto findByUserName(string userName);
  UserDto create(CreateUserInput input);
  UserDto update(string id, UpdateUserInput input);
  void setPassword(string id, string newPassword);
  /// Own password change: verifies the current password first.
  void changeOwnPassword(string id, string currentPassword, string newPassword);
  void remove(string id);
  /// Verifies the credentials of an active user; throws AuthenticationFailedException.
  UserDto authenticate(string userName, string password);
}
