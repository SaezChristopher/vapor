import HTTP
import HTTPRouting

extension Droplet: Responder {
    /// Returns a response to the given request
    ///
    /// - parameter request: received request
    /// - throws: error if something fails in finding response
    /// - returns: response if possible
    public func respond(to request: Request) throws -> Response {
        log.info("\(request.method) \(request.uri.path)")

        var responder: Responder
        let request = request

        /// The HEAD method is identical to GET.
        ///
        /// https://tools.ietf.org/html/rfc2616#section-9.4
        let originalMethod = request.method
        if case .head = request.method {
            request.method = .get
        }

        let routerResponder: Request.Handler = Request.Handler { [weak self] request in
            // Routed handler
            if let handler = self?.router.route(request, with: request) {
                return try handler.respond(to: request)
            } else {
                // Default not found handler
                let normal: [HTTP.Method] = [.get, .post, .put, .patch, .delete]

                if normal.contains(request.method) {
                    throw Abort.notFound
                } else if case .options = request.method {
                    return Response(status: .ok, headers: [
                        "Allow": "OPTIONS"
                    ])
                } else {
                    return Response(status: .notImplemented)
                }
            }
        }

        // Loop through middlewares in order, then pass result to router responder
        responder = middleware.chain(to: routerResponder)

        let response: Response
        
        do {
            response = try responder.respond(to: request)

            if response.headers["Content-Type"] == nil && response.status != .notModified {
                log.warning("Response had no 'Content-Type' header.")
            }
        } catch {
            // get status
            let status: Status

            if let abort = error as? AbortError {
                status = abort.status
            } else {
                status = .internalServerError
            }

            if let debuggable = error as? Debuggable {
                log.error(debuggable.loggable)
            } else {
                let type = String(reflecting: type(of: error))
                log.error("[\(type): \(error)]")
                log.info("Conform '\(type)' to Debugging.Debuggable to provide more debug information.")
            }

            if request.accept.prefers("html") {
                response = try view.make(error).makeResponse()
            } else {
                var json = JSON([:])
                try json.set("error", true)
                if environment == .production {
                    try json.set("reason", status.reasonPhrase)
                } else {
                    if let abort = error as? AbortError {
                        try json.set("reason", abort.status.reasonPhrase)
                        try json.set("metadata", abort.metadata)
                    }
                    if let debug = error as? Debuggable {
                        try json.set("reason", debug.reason)
                        try json.set("identifier", debug.fullIdentifier)
                        if !debug.possibleCauses.isEmpty {
                            try json.set("possibleCauses", debug.possibleCauses)
                        }
                        if !debug.suggestedFixes.isEmpty {
                            try json.set("suggestedFixes", debug.suggestedFixes)
                        }
                        if !debug.documentationLinks.isEmpty {
                            try json.set("documentationLinks", debug.documentationLinks)
                        }
                        if !debug.stackOverflowQuestions.isEmpty {
                            try json.set("stackOverflowQuestions", debug.stackOverflowQuestions)
                        }
                        if !debug.gitHubIssues.isEmpty {
                            try json.set("gitHubIssues", debug.gitHubIssues)
                        }
                    }
                }
                let errorResponse = Response(status: status)
                errorResponse.json = json

                response = errorResponse
            }
        }

        /// The server MUST NOT return a message-body in the response for HEAD.
        ///
        /// https://tools.ietf.org/html/rfc2616#section-9.4
        if case .head = originalMethod {
            // TODO: What if body is set to chunked¿?
            response.body = .data([])
        }
        
        return response
    }
}

extension Debuggable {
    var loggable: String {
        var print: [String] = []

        print.append("\(Self.readableName): \(reason)")
        print.append("Identifier: \(fullIdentifier)")

        if !possibleCauses.isEmpty {
            print.append("Possible Causes: \(possibleCauses.commaSeparated)")
        }

        if !suggestedFixes.isEmpty {
            print.append("Suggested Fixes: \(suggestedFixes.commaSeparated)")
        }

        if !documentationLinks.isEmpty {
            print.append("Documentation Links: \(documentationLinks.commaSeparated)")
        }

        if !stackOverflowQuestions.isEmpty {
            print.append("Stack Overflow Questions: \(stackOverflowQuestions.commaSeparated)")
        }

        if !gitHubIssues.isEmpty {
            print.append("GitHub Issues: \(gitHubIssues.commaSeparated)")
        }

        return print.map { "[\($0)]" }.joined(separator: " ")
    }
}

extension Sequence where Iterator.Element == String {
    var commaSeparated: String {
        return joined(separator: ", ")
    }
}
