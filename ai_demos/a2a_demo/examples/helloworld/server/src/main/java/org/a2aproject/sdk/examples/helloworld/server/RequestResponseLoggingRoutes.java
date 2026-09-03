package org.a2aproject.sdk.examples.helloworld.server;

import jakarta.enterprise.event.Observes;
import jakarta.inject.Singleton;

import io.vertx.ext.web.Router;
import io.vertx.ext.web.handler.BodyHandler;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Logs every HTTP request/response so the wire protocol is visible in the console
 * during the live demo. The A2A endpoints here (see {@code A2AServerRoutes} in the
 * SDK's {@code a2a-java-sdk-reference-jsonrpc} module) are registered directly on the
 * Vert.x Web {@link Router} via {@code @Observes Router}, not as JAX-RS resources, so
 * this filter hooks the same Router rather than a JAX-RS {@code ContainerRequestFilter}
 * (which would never fire here).
 */
@Singleton
public class RequestResponseLoggingRoutes {

    private static final Logger LOG = LoggerFactory.getLogger(RequestResponseLoggingRoutes.class);

    void setupLogging(@Observes Router router) {
        // Order -1 so this runs before the SDK's own routes (registered at default order).
        router.route().order(-1).handler(BodyHandler.create());
        router.route().order(-1).handler(ctx -> {
            // BREAKPOINT: pause on the raw JSON-RPC envelope for the discovery GET and the message/stream POST
            String method = ctx.request().method().name();
            String path = ctx.request().path();
            String body = ctx.body() != null ? ctx.body().asString() : null;
            if (body != null && !body.isEmpty()) {
                LOG.info(">>> {} {} body={}", method, path, body);
            } else {
                LOG.info(">>> {} {}", method, path);
            }

            ctx.addBodyEndHandler(v -> {
                // BREAKPOINT: pause on the raw JSON-RPC envelope for the discovery GET and the message/stream POST
                LOG.info("<<< {} {} {}", method, path, ctx.response().getStatusCode());
            });

            ctx.next();
        });
    }
}
