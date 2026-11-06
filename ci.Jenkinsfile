pipeline {
    agent any

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Run CI') {
            steps {
                script {
                    echo "Compiling and running tests for sigeca-api:"
                    sh "chmod +x ./build.sh"
                    sh "sh ./build.sh"
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        success {
            echo "SUCCESS: Compilation finished and tests passed."
        }
        failure {
            echo "FAILED: Check logs above for details."
        }
    }
}