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
            .on(.PATCH, "accept", use: acceptInvitation)
        
        friend
            .grouped(AccessToken.authenticator())
            .on(.PATCH, "reject", use: rejectInvitation)
        
        friend
            .grouped(AccessToken.authenticator())
            .on(.GET, "getInvites", use: getPendingInvitations)
        
        friend
            .grouped(AccessToken.authenticator())
            .on(.GET, "getFriends", use: getFriendList)
    }

    // MARK: - Invitation
    
    func sendInvite(req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let data = try req.content.decode(FriendInvitation.Create.self)
        
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
    
    func acceptInvitation(_ req: Request) async throws -> Response {
        let invitation = try await UserInInvitation.validation(req)
        
        invitation.status = .accepted
        try await invitation.update(on: req.db(.psql))
        
        let friend = try await Friend(
            uid1: invitation.$requestor.get(on: req.db(.psql)),
            uid2: invitation.$addressee.get(on: req.db(.psql))
        )
        try await friend.save(on: req.db(.psql))
        
        return .init(status: .ok)
    }
    
    func rejectInvitation(_ req: Request) async throws -> Response {
        let invitation = try await UserInInvitation.validation(req)
        
        invitation.status = .rejected
        try await invitation.update(on: req.db(.psql))
        
        return .init(status: .ok)
    }
    
    func getPendingInvitations(_ req: Request) async throws -> [FriendInvitation.Get] {
        let user = try req.auth.require(User.self)
        
        let invitations = try await FriendInvitation.query(on: req.db(.psql))
            .filter(\.$addressee.$id == user.requireID())
            .filter(\.$status == .pending)
            .with(\.$requestor)
            .all()
        
        return try invitations.map { invitation in
            try FriendInvitation.Get(
                id: invitation.requireID(),
                requestor: User.Get(
                    id: invitation.requestor.requireID(),
                    account: invitation.requestor.account,
                    mail: invitation.requestor.mail,
                    name: invitation.requestor.name,
                    avatar: invitation.requestor.avatar
                ),
                status: invitation.status
            )
        }
    }
    
    // MARK: - Friend
    
    func getFriendList(_ req: Request) async throws -> [User.Get] {
        let user = try req.auth.require(User.self)
        
        let friendList = try await Friend.query(on: req.db(.psql))
            .group(.or) { group in
                group.filter(\.$uid1.$id == user.id!)
                group.filter(\.$uid2.$id == user.id!)
            }
            .with(\.$uid1)
            .with(\.$uid2)
            .all()
        
        var friends = try friendList.map { friendData in
            var friend: User
            if friendData.uid1.id == user.id {
                friend = friendData.uid2
            } else {
                friend = friendData.uid1
            }
            
            return try User.Get(
                id: friend.requireID(),
                account: friend.account,
                mail: friend.mail,
                name: friend.name,
                avatar: friend.avatar
            )
        }
        
        return friends
    }
}
