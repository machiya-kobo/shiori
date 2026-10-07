# mac-bridge (shiori classic/bridge): Shiori for Classic Macintosh's plain-HTTP way into Hister and Kura.
# Stdlib Python only. Build context: this directory. Runs as uid 1000 with no state.
FROM public.ecr.aws/docker/library/python:3.13-alpine
RUN adduser -D -u 1000 -h /nonexistent -s /sbin/nologin bridge
WORKDIR /app
COPY bridge.py /app/
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
USER 1000:1000
EXPOSE 8070 8071
HEALTHCHECK --interval=60s --timeout=5s --start-period=5s --retries=3 \
  CMD python3 -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8070/healthz', timeout=4).read() == b'ok\n' else 1)"
CMD ["python3", "/app/bridge.py"]
