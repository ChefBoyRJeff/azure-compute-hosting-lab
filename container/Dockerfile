# Base image from Microsoft Container Registry (avoids Docker Hub pull limits during 'az acr build').
FROM mcr.microsoft.com/azurelinux/base/python:3.12

WORKDIR /app
COPY app.py .

ENV APP_VERSION=v1 \
    PORT=8080
EXPOSE 8080

# Run as a non-root user.
USER 1000
CMD ["python3", "app.py"]
