pipeline {
    agent any

    parameters {
        string(name: 'BRANCH_NAME', defaultValue: 'main', description: 'Branch to build and deploy')
    }

    environment {
        ECR_REGISTRY = '297457984580.dkr.ecr.af-south-1.amazonaws.com'
        ECR_REPOSITORY = 'sigeca-openlmis-referencedata'
        AWS_REGION = 'af-south-1'
        DEPLOYMENT_HOST = 'i-00cfaa0043be9e14c'
    }

    stages {
        stage('Checkout') {
            steps {
                script {
                    def branchToBuild = params.BRANCH_NAME?.trim() ? params.BRANCH_NAME : 'main'

                    echo "Checkout out branch: ${branchToBuild}"

                    checkout([
                        $class: 'GitSCM',
                        branches: [[name: "*/${branchToBuild}"]],
                        doGenerateSubmoduleConfigurations: false,
                        extensions: [[$class: 'CleanBeforeCheckout']],
                        submoduleCfg: [],
                        userRemoteConfigs: [[
                            url: scm.userRemoteConfigs[0].url,
                            credentialsId: scm.userRemoteConfigs[0].credentialsId,
                            refspec: '+refs/heads/*:refs/remotes/origin/*'
                        ]]
                    ])

                    env.BUILD_DATE = sh(script: "date +%Y%m%d", returnStdout: true).trim()
                    env.IMAGE_TAG = "${env.BUILD_DATE}-${env.BUILD_NUMBER}"
                    echo "Building image with tag: ${env.IMAGE_TAG}"
                }
            }
        }
        stage('Build Application') {
            steps {
                script {
                    def uid = sh(script: 'id -u', returnStdout: true).trim()
                    def gid = sh(script: 'id -g', returnStdout: true).trim()
                    def commandStatus = sh(
                        script: """
#!/bin/sh

rm -rf node_modules build .gradle
docker ps -q | xargs -r docker stop

DOCKER_IMAGE="amazoncorretto:8u342-alpine3.16"
DOCKER_CMD="apk add --no-cache npm freetype ttf-dejavu fontconfig su-exec && \\
    npm config set loglevel verbose && \\
    install -o ${uid} -g ${gid} -d build/resources/main && \\
    chown -R ${uid}:${gid} /app && \\
    su-exec ${uid}:${gid} sh -c ' \\
        export HOME=/app && \\
        npm install 2>&1 || { find /app/.npm/_logs -type f -print -exec cat {} \\; 2>/dev/null; exit 1; } && \\
        ./gradlew clean build -x checkstyleMain -x checkstyleTest -x pmdMain -x pmdTest -x jacocoTestCoverageVerification --no-build-cache \\
    '"

docker run --rm --platform=linux/amd64 --user root --network=host -v "\$(pwd)":/app -w /app "\${DOCKER_IMAGE}" sh -c "\${DOCKER_CMD}"
                            """,
                            returnStdout: true
                        ).trim()
                    echo "Command status: ${commandStatus}"
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    echo "Building Docker image: ${ECR_REGISTRY}/${ECR_REPOSITORY}:${env.IMAGE_TAG}"
                    dockerImage = docker.build("${ECR_REGISTRY}/${ECR_REPOSITORY}:${env.IMAGE_TAG}", "--no-cache .")
                    dockerImage.tag("latest")
                }
            }
        }

        stage('Push to ECR') {
            steps {
                script {
                    echo "Logging into ECR and pushing image"
                    sh "aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}"
                    dockerImage.push("${env.IMAGE_TAG}")
                    dockerImage.push("latest")
                    echo "Successfully pushed ${ECR_REPOSITORY}:${env.IMAGE_TAG} to ECR"
                }
            }
        }

    }

    post {
        always {
            cleanWs()
        }
        success {
            echo "SUCCESS: Pushing ${ECR_REPOSITORY}:${env.IMAGE_TAG} completed successfully"
            echo "Build: #${env.BUILD_NUMBER}"
            echo "Image Tag: ${env.IMAGE_TAG}"
        }
        failure {
            echo "FAILED: Pushing ${ECR_REPOSITORY}:${env.IMAGE_TAG} failed"
            echo "Check logs above for details"
        }
    }
}