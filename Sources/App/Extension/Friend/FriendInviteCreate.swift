//
//  FriendInviteCreate.swift
//
//
//  Created by Dong on 2024/7/7.
//

import Fluent
import Vapor

extension Friend {
    struct Create: Content {
        var addressee: UUID
    }
}


extension Friend.Create: Validatable {
    static func validations(_ validations: inout Validations) {
        validations.add("addressee", as: UUID.self, required: true)
    }
}
