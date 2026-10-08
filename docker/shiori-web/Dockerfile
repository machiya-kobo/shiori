# shiori-web: Shiori's search page and web app behind nginx, in one image for every deployment.
#
#   docker build -f docker/shiori-web/Dockerfile -t shiori-web .          (from the repository root)
#
# The pages are built once, here, with their settings left as placeholders. When the container starts,
# configure.py checks the settings it is given (SHIORI_HISTER_URL and SHIORI_SEARXNG_URL are required, the rest
# optional), stamps them into a copy of the pages and writes nginx's config, so nothing is baked in. It runs as a
# non-root user and works with a read-only root filesystem and a tmpfs on /tmp. web/README.md ("In a container")
# lists the settings. Run tools/pin-bases before a release: both bases are pinned by digest.

FROM public.ecr.aws/docker/library/python:3.13-alpine@sha256:2d9aefe2fef018a7eb2c13064c89c71929800fd2e5dccdbf52ea5da5bb8d929a AS build
RUN apk add --no-cache bash
WORKDIR /src
COPY . .
# A build with no git says its commit and the Hister release it is built against itself.
ARG SHIORI_BUILD_ID=unknown
ARG SHIORI_HISTER_RELEASE=
ENV SHIORI_BUILD_ID=$SHIORI_BUILD_ID SHIORI_HISTER_RELEASE=$SHIORI_HISTER_RELEASE
# Settings (and the page's own address, and the status link) are filled in when the container starts.
RUN scripts/build-web.sh /dist/search http://shiori-web.invalid/ @runtime \
 && scripts/build-pwa.sh /dist/app @runtime

FROM public.ecr.aws/nginx/nginx-unprivileged:stable-alpine@sha256:15c994d10d6d78658721c3bcafff14cb281fba2a4bdf9d5ba92c416a472516e3
USER root
RUN apk add --no-cache python3 ca-certificates
COPY --from=build /dist /opt/shiori/dist
COPY scripts/stamp-env.py scripts/rooms-stamp.py scripts/status-link.py /opt/shiori/scripts/
COPY docker/shiori-web/configure.py docker/shiori-web/nginx.conf docker/shiori-web/entrypoint.sh /opt/shiori/
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
USER 101
EXPOSE 8080 8081
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
ENTRYPOINT ["/opt/shiori/entrypoint.sh"]
LABEL org.opencontainers.image.title="shiori-web" \
      org.opencontainers.image.description="Shiori's search page and web app: search your Hister and SearXNG together" \
      org.opencontainers.image.source="https://github.com/machiya-kobo/shiori" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later"
