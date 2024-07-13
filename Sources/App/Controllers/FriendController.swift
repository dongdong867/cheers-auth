//
//  FriendController.swift
//
//
//  Created by Dong on 2024/6/25.
//

import Fluent
import Foundation
import Vapor

struct FriendController: RouteCollection {
    func boot(routes: any Vapor.RoutesBuilder) throws {
        let friend = routes.grouped("friend")
        
        friend
            .grouped(AccessToken.authenticator())
            .on(.POST, "sendInvite", use: sendInvite)
        
        friend
            .grouped(AccessToken.authenticator())
            .on(.PATCH, "accept", use: acceptFriendInvitation)
    }

    func sendInvite(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let data = try req.content.decode(Friend.Create.self)
        
        guard let addressee = try await User.query(on: req.db(.psql))
            .filter(\.$id == data.addressee)
            .first()
        else { return .init(status: .badRequest) }
        
        let invitation = try await FriendInvitation
            .query(on: req.db(.psql))
            .group(.or) { group in
                group
                    .group { asRequestor in
                        asRequestor
                            .filter(\.$requestor.$id == user.id!)
                            .filter(\.$addressee.$id == addressee.id!)
                    }
                    .group { asAddressee in
                        asAddressee
                            .filter(\.$requestor.$id == addressee.id!)
                            .filter(\.$addressee.$id == user.id!)
                    }
            }.first()
        
        if invitation != nil {
            if invitation!.status == .rejected {
                invitation!.status = .pending
                try await invitation!.update(on: req.db(.psql))
                
                return .init(status: .ok)
            }
            
            return .init(status: .conflict)
        }
        
        let createInvitation = try FriendInvitation(
            requestor: user,
            addressee: addressee
        )
        try await createInvitation.save(on: req.db(.psql))
        
        return .init(status: .ok)
    }
    
    func acceptFriendInvitation(_ req: Request) async throws -> Response {
        let (_, invitation) = try await validateUserInInvitation(req)
        
        invitation.status = .accepted
        try await invitation.update(on: req.db(.psql))
        
        let friend = try await Friend(
            uid1: invitation.$requestor.get(on: req.db(.psql)),
            uid2: invitation.$addressee.get(on: req.db(.psql))
        )
        try await friend.save(on: req.db(.psql))
        
        return .init(status: .ok)
    }
}


extension FriendController {
    func validateUserInInvitation(_ req: Request) async throws -> (User, FriendInvitation) {
        let user = try req.auth.require(User.self)
        
        guard let requestId = try? req.query.get<String>(String.self, at: "id"),
              let requestUuid = UUID(uuidString: requestId)
        else { throw Abort(.badRequest) }
        
        guard let invitation = try await FriendInvitation.query(on: req.db(.psql))
            .filter(\.$id == requestUuid)
            .filter(\.$addressee.$id == user.id!)
            .first()
        else { throw Abort(.forbidden) }
        
        return (user, invitation)
    }
}