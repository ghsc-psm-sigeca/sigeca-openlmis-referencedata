pipeline {
    agent any

    environment {
        ECR_REGISTRY = '823413233235.dkr.ecr.us-east-1.amazonaws.com'
        ECR_REPOSITORY = 'sigeca-openlmis-referencedata'
        AWS_REGION = 'us-east-1'
        DEPLOYMENT_HOST = 'i-04b006ea4291dc665'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.BUILD_DATE = sh(script: "date +%Y%m%d", returnStdout: true).trim()
                    env.IMAGE_TAG = "${env.BUILD_DATE}-${env.BUILD_NUMBER}"
                    echo "Building image with tag: ${env.IMAGE_TAG}"
                }
            }
        }

        stage('Build Application') {
            steps {
                script {
                    echo "Building Java application..."
                    sh "sh ./compile-then-tests.sh"
                    echo "Application build completed"
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
                    currentBuild.description = "${env.IMAGE_TAG}"
                }
            }
        }

        stage('Deploy to EC2') {
            steps {
                script {
                    echo "Starting deployment to ${DEPLOYMENT_HOST}"

                    // Deploy via AWS SSM (secure, no SSH keys needed)
                    def deployCommand = sh(
                        script: """
                            aws ssm send-command \\
                                --instance-ids "${DEPLOYMENT_HOST}" \\
                                --document-name "AWS-RunShellScript" \\
                                --parameters 'commands=["bash", "cd /home/ssm-user", "/home/ssm-user/deployment-scripts/deploy-sigeca-api.sh ${env.IMAGE_TAG}"]' \\
                                --region ${AWS_REGION} \\
                                --output text \\
                                --query 'Command.CommandId'
                        """,
                        returnStdout: true
                    ).trim()

                    echo "SSM Command ID: ${deployCommand}"

                    // Wait for command completion and check results
                    def maxAttempts = 12  // 2 minutes max wait
                    def attempt = 1
                    def commandStatus = ""

                    while (attempt <= maxAttempts) {
                        echo "Checking deployment status (attempt ${attempt}/${maxAttempts})..."

                        commandStatus = sh(
                            script: """
                                aws ssm get-command-invocation \\
                                    --command-id ${deployCommand} \\
                                    --instance-id ${DEPLOYMENT_HOST} \\
                                    --region ${AWS_REGION} \\
                                    --query 'Status' \\
                                    --output text
                            """,
                            returnStdout: true
                        ).trim()

                        echo "Command status: ${commandStatus}"

                        if (commandStatus == "Success") {
                            echo "Deployment completed successfully"
                            break
                        } else if (commandStatus == "Failed") {
                            // Get the error details
                            def errorOutput = sh(
                                script: """
                                    aws ssm get-command-invocation \\
                                        --command-id ${deployCommand} \\
                                        --instance-id ${DEPLOYMENT_HOST} \\
                                        --region ${AWS_REGION} \\
                                        --query 'StandardErrorContent' \\
                                        --output text
                                """,
                                returnStdout: true
                            ).trim()

                            error("Deployment failed: ${errorOutput}")
                        }

                        sleep(10)
                        attempt++
                    }

                    if (commandStatus != "Success") {
                        error("Deployment timed out or failed. Status: ${commandStatus}")
                    }
                }
            }
        }

        stage('Health Check') {
            steps {
                script {
                    echo "Waiting for service to be healthy..."
                    sleep(5)

                    def healthCheckPassed = false
                    def maxHealthAttempts = 60
                    def healthAttempt = 1

                    while (healthAttempt <= maxHealthAttempts && !healthCheckPassed) {
                        try {
                            echo "Health check attempt ${healthAttempt}/${maxHealthAttempts}"

                            def response = sh(
                                script: "curl -f -s -o /dev/null -w '%{http_code}' https://app.ang-elmis-dev.net/ || echo 'failed'",
                                returnStdout: true
                            ).trim()

                            if (response == "200") {
                                echo "Health check passed - service is responding"
                                healthCheckPassed = true
                            } else {
                                echo "Health check failed - HTTP status: ${response}"
                                sleep(5)
                                healthAttempt++
                            }
                        } catch (Exception e) {
                            echo "Health check attempt failed: ${e.getMessage()}"
                            sleep(5)
                            healthAttempt++
                        }
                    }

                    if (!healthCheckPassed) {
                        error("Health check failed - service may not be responding correctly")
                    }
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        success {
            echo "SUCCESS: Deployment of ${ECR_REPOSITORY}:${env.IMAGE_TAG} completed successfully"
            echo "Application URL: https://app.ang-elmis-dev.net"
            echo "Build: #${env.BUILD_NUMBER}"
            echo "Image Tag: ${env.IMAGE_TAG}"
        }
        failure {
            echo "FAILED: Deployment of ${ECR_REPOSITORY}:${env.IMAGE_TAG} failed"
            echo "Check logs above for details"
            echo "Consider rolling back to previous version if needed"
        }
    }
}