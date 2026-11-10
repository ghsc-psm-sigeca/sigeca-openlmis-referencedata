pipeline {
    agent any

    parameters {
        string(name: 'BRANCH_NAME', defaultValue: 'main', description: 'Branch to build and deploy')
    }

    environment {
        ECR_REGISTRY = '823413233235.dkr.ecr.us-east-1.amazonaws.com'
        ECR_REPOSITORY = 'sigeca-openlmis-referencedata'
        AWS_REGION = 'us-east-1'
        DEPLOYMENT_HOST = 'i-04b006ea4291dc665'
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
                    echo "Building Java application..."
                    sh 'sh ./compile-then-tests.sh'
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