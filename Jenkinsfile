// =============================================================================
// Jenkinsfile — Student Expense Tracker
//
// Pipeline stages (mirrors the GitHub Actions CI workflow):
//
//   Checkout → Lint → Security Scan → Test → Docker Build → Smoke Test
//
// Requirements (Jenkins plugins):
//   - Pipeline          (declarative pipeline syntax)
//   - Docker Pipeline   (docker { image '...' } agent blocks)
//   - Git               (checkout scm)
//
// Jenkins must be started with the Docker socket mounted:
//   docker run -v /var/run/docker.sock:/var/run/docker.sock ...
// =============================================================================

pipeline {

    // Run on any available agent (the Jenkins controller itself in local dev)
    agent any

    // ── Global environment variables ─────────────────────────────────────────
    environment {
        IMAGE_NAME = 'student-expense-tracker'
        IMAGE_TAG  = "build-${env.BUILD_NUMBER}"   // unique per build
        FLASK_ENV  = 'testing'
    }

    // ── Pipeline options ──────────────────────────────────────────────────────
    options {
        // Abort the build if it takes longer than 15 minutes
        timeout(time: 15, unit: 'MINUTES')

        // Keep the last 5 build logs; discard older ones to save disk space
        buildDiscarder(logRotator(numToKeepStr: '5'))

        // Show timestamps in every console log line
        timestamps()
    }

    // =========================================================================
    // STAGES
    // =========================================================================
    stages {

        // ── Stage 1: Checkout ─────────────────────────────────────────────────
        stage('Checkout') {
            steps {
                echo "Checking out branch: ${env.BRANCH_NAME ?: 'local'}"
                checkout scm
            }
        }

        // ── Stage 2: Lint ─────────────────────────────────────────────────────
        // Uses a throwaway Python 3.12 container — no Python needed on Jenkins host.
        // ruff checks code style and formatting (same tool as GitHub Actions).
        stage('Lint') {
            agent {
                docker {
                    image 'python:3.12-slim'
                    reuseNode true          // run on same workspace as outer agent
                    args '-u root'          // run as root so pip can install packages
                }
            }
            steps {
                echo 'Running ruff lint + format check…'
                sh '''
                    pip install ruff --quiet
                    ruff check tracker/ config.py
                    ruff format tracker/ config.py --check --diff
                '''
            }
        }

        // ── Stage 3: Security Scan ────────────────────────────────────────────
        // bandit  → scans Python source for security anti-patterns
        // pip-audit → checks packages against CVE database
        stage('Security Scan') {
            agent {
                docker {
                    image 'python:3.12-slim'
                    reuseNode true
                    args '-u root'
                }
            }
            steps {
                echo 'Running bandit (SAST) and pip-audit (CVE scan)…'
                sh '''
                    pip install bandit pip-audit --quiet

                    echo "--- bandit ---"
                    bandit -r tracker/ config.py -ll -q

                    echo "--- pip-audit ---"
                    pip-audit -r requirements.txt --progress-spinner off
                '''
            }
        }

        // ── Stage 4: Test ─────────────────────────────────────────────────────
        // pytest runs all 20 tests against an in-memory SQLite database.
        // No running Postgres needed.
        stage('Test') {
            agent {
                docker {
                    image 'python:3.12-slim'
                    reuseNode true
                    args '-u root'
                }
            }
            steps {
                echo 'Installing dependencies and running pytest…'
                sh '''
                    pip install -r requirements.txt --quiet
                    pytest test_app.py -v --tb=short
                '''
            }
        }

        // ── Stage 5: Docker Build ─────────────────────────────────────────────
        // Builds the production Docker image using the multi-stage Dockerfile.
        // Jenkins uses the host Docker daemon (via the mounted docker.sock).
        stage('Docker Build') {
            steps {
                echo "Building Docker image: ${IMAGE_NAME}:${IMAGE_TAG}"
                sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
                sh "docker tag  ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest"
                echo "Image built and tagged as ${IMAGE_NAME}:latest"
            }
        }

        // ── Stage 6: Smoke Test ───────────────────────────────────────────────
        // Starts the freshly built container and hits /health.
        // Uses SQLite so no Postgres needed.
        // NOTE: Jenkins itself runs inside Docker, so we cannot use localhost:PORT
        // to reach a sibling container. Instead we get the container's internal
        // bridge IP and curl that directly on port 5000.
        stage('Smoke Test') {
            steps {
                echo 'Starting container and testing /health endpoint…'
                sh '''
                    # Start the container (no port publish needed — we use internal IP)
                    docker run --detach --name jenkins-smoke-${BUILD_NUMBER} \
                        --env DATABASE_URL="sqlite:////tmp/ci.db" \
                        --env SECRET_KEY="jenkins-smoke-test-only" \
                        --env FLASK_ENV="development" \
                        student-expense-tracker:latest

                    # Get the container's internal Docker bridge IP
                    SMOKE_IP=$(docker inspect -f \
                        '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
                        jenkins-smoke-${BUILD_NUMBER})
                    echo "Smoke container IP: $SMOKE_IP"

                    echo "Waiting for app to be ready..."
                    for i in $(seq 1 15); do
                        if curl -sf http://${SMOKE_IP}:5000/health; then
                            echo "App is healthy after $i attempt(s)"
                            break
                        fi
                        echo "  attempt $i/15 — sleeping 3s"
                        sleep 3
                    done

                    # Hard fail if app never became healthy
                    curl --fail --silent http://${SMOKE_IP}:5000/health \
                        || { echo "App never became healthy"; docker logs jenkins-smoke-${BUILD_NUMBER}; exit 1; }
                '''
            }
            post {
                always {
                    // Clean up the smoke test container whether it passed or failed
                    sh '''
                        docker stop jenkins-smoke-${BUILD_NUMBER} 2>/dev/null || true
                        docker rm   jenkins-smoke-${BUILD_NUMBER} 2>/dev/null || true
                    '''
                }
            }
        }

    }

    // =========================================================================
    // POST — runs after all stages finish
    // =========================================================================
    post {

        success {
            echo """
            ============================================
            BUILD #${env.BUILD_NUMBER} PASSED
            Image: ${IMAGE_NAME}:${IMAGE_TAG}
            All stages: Lint, Security, Test, Build, Smoke Test
            ============================================
            """
        }

        failure {
            echo """
            ============================================
            BUILD #${env.BUILD_NUMBER} FAILED
            Check the stage logs above for details.
            ============================================
            """
        }

        always {
            // Clean the workspace after every build to free disk space
            cleanWs()
        }

    }
}
