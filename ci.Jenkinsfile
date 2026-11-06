pipeline {
    agent any

    stages {
        stage('Run CI') {
            steps {
                echo 'Compiling and running tests for reference-data:'
                sh 'sh ./compile-then-tests.sh'
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