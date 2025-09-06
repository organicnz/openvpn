# Build stage for dependency management and optimization
FROM alpine:3.18 AS builder

# Install build dependencies
RUN apk add --no-cache \
    php82 \
    php82-phar \
    php82-json \
    php82-openssl \
    curl

# Validate and optimize PHP files
COPY index.php /tmp/app/
RUN php82 -l /tmp/app/index.php && \
    php82 -d opcache.enable_cli=1 -d opcache.preload=/tmp/app/index.php -r "echo 'PHP validation passed';"

# Production stage
FROM alpine:3.18 AS production

# Security: Create non-root user
RUN addgroup -g 1000 -S appgroup && \
    adduser -u 1000 -S appuser -G appgroup

# Install runtime packages only
RUN apk add --no-cache \
    nginx=1.24.0-r7 \
    supervisor=4.2.5-r4 \
    php82=8.2.18-r0 \
    php82-fpm=8.2.18-r0 \
    php82-json=8.2.18-r0 \
    php82-session=8.2.18-r0 \
    php82-opcache=8.2.18-r0 \
    php82-ctype=8.2.18-r0 \
    php82-dom=8.2.18-r0 \
    tini=0.19.0-r1 && \
    rm -rf /var/cache/apk/*

# Create necessary directories with proper permissions
RUN mkdir -p /app /run/nginx /var/log/supervisor /var/log/nginx && \
    chown -R appuser:appgroup /app /run/nginx /var/log/supervisor /var/log/nginx && \
    chmod 755 /app

# Copy validated files from builder
COPY --from=builder --chown=appuser:appgroup /tmp/app/ /app/
COPY --chown=root:root nginx.conf /etc/nginx/nginx.conf
COPY --chown=root:root supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY --chown=root:root php-fpm.conf /etc/php82/php-fpm.d/www.conf

# Security hardening
RUN chmod 644 /etc/nginx/nginx.conf /etc/supervisor/conf.d/supervisord.conf && \
    chmod 644 /etc/php82/php-fpm.d/www.conf && \
    rm -f /etc/nginx/conf.d/default.conf

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

EXPOSE 80

# Use tini as init system
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]