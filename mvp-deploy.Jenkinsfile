pipeline {
    agent any

    environment {
        ECR_REGISTRY = '297457984580.dkr.ecr.af-south-1.amazonaws.com'
        ECR_REPOSITORY = 'sigeca-openlmis-referencedata'
        AWS_REGION = 'af-south-1'
        DEPLOYMENT_HOST = 'i-0acbb493536ae68c9'
    }

    stages {

        stage('Deploy to EC2') {
            steps {
                script {
                    echo "Starting deployment to ${DEPLOYMENT_HOST}"

                    // Deploy via AWS SSM (secure, no SSH keys needed)
                    // Ship the deploy script from the workspace to the host, so it does not need to be pre-installed
                    def scriptBase64 = sh(
                        script: "base64 < deploy-referencedata.sh | tr -d '\\n'",
                        returnStdout: true
                    ).trim()

                    def deployCommand = sh(
                        script: """
                            aws ssm send-command \\
                                --instance-ids "${DEPLOYMENT_HOST}" \\
                                --document-name "AWS-RunShellScript" \\
                                --parameters 'commands=["echo ${scriptBase64} | base64 -d > /tmp/deploy-referencedata.sh", "bash /tmp/deploy-referencedata.sh ${params.IMAGE_TAG}"]' \\
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
                    sleep(30)

                    def healthCheckPassed = false
                    def maxHealthAttempts = 6  // 1 minute max wait
                    def healthAttempt = 1

                    while (healthAttempt <= maxHealthAttempts && !healthCheckPassed) {
                        try {
                            echo "Health check attempt ${healthAttempt}/${maxHealthAttempts}"

                            def response = sh(
                                script: "curl -f -s -o /dev/null -w '%{http_code}' https://app.uat.sigeca.org/ || echo 'failed'",
                                returnStdout: true
                            ).trim()

                            if (response == "200") {
                                echo "Health check passed - service is responding"
                                healthCheckPassed = true
                            } else {
                                echo "Health check failed - HTTP status: ${response}"
                                sleep(10)
                                healthAttempt++
                            }
                        } catch (Exception e) {
                            echo "Health check attempt failed: ${e.getMessage()}"
                            sleep(10)
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
            echo "SUCCESS: Deployment of ${ECR_REPOSITORY}:${params.IMAGE_TAG} completed successfully"
            echo "Application URL: https://app.uat.sigeca.org"
            echo "Build: #${env.BUILD_NUMBER}"
            echo "Image Tag: ${params.IMAGE_TAG}"
        }
        failure {
            echo "FAILED: Deployment of ${ECR_REPOSITORY}:${params.IMAGE_TAG} failed"
            echo "Check logs above for details"
            echo "Consider rolling back to previous version if needed"
        }
    }
}