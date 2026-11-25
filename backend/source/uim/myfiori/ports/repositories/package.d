/// Driven ports for business data access.
module uim.myfiori.ports.repositories;

@safe:

import uim.myfiori.domain.entities;
import uim.myfiori.domain.types : EntityId;

interface IRepository(T) {
  T[] findAll();
  /// Returns null if no entity with this id exists.
  T findById(EntityId id);
  void save(T entity);
  bool remove(EntityId id);
}

interface IProjectRepository : IRepository!DProject {}

interface ITargetObjectRepository : IRepository!DTargetObject {
  DTargetObject[] findByProject(EntityId projectId);
}

interface IRequirementRepository : IRepository!DRequirement {
  DRequirement[] findByProject(EntityId projectId);
  DRequirement[] findByTargetObject(EntityId targetObjectId);
}

interface IRiskRepository : IRepository!DRisk {
  DRisk[] findByProject(EntityId projectId);
  DRisk[] findByTargetObject(EntityId targetObjectId);
}

interface IUserRepository : IRepository!DUser {
  /// Returns null if no user with this (normalised) login name exists.
  DUser findByUserName(string userName);
}
