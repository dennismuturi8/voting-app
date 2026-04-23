Example Voting App
A simple distributed application running across multiple Docker containers.

Getting started
Download Docker Desktop for Mac or Windows. Docker Compose will be automatically installed. On Linux, make sure you have the latest version of Compose.

This solution uses Python, Node.js, .NET, with Redis for messaging and Postgres for storage.

Run in this directory to build and run the app:

docker compose up
The vote app will be running at http://localhost:8080, and the results will be at http://localhost:8081.

Alternately, if you want to run it on a Docker Swarm, first make sure you have a swarm. If you don't, run:

docker swarm init
Once you have your swarm, in this directory run:

docker stack deploy --compose-file docker-stack.yml vote
Run the app in Kubernetes
The folder k8s-specifications contains the YAML specifications of the Voting App's services.

Run the following command to create the deployments and services. Note it will create these resources in your current namespace (default if you haven't changed it.)

kubectl create -f k8s-specifications/
The vote web app is then available on port 31000 on each host of the cluster, the result web app is available on port 31001.

To remove them, run:

kubectl delete -f k8s-specifications/
Architecture
Architecture diagram

A front-end web app in Python which lets you vote between two options
A Redis which collects new votes
A .NET worker which consumes votes and stores them in…
A Postgres database backed by a Docker volume
A Node.js web app which shows the results of the voting in real time
Notes
The voting application only accepts one vote per client browser. It does not register additional votes if a vote has already been submitted from a client.

This isn't an example of a properly architected perfectly designed distributed app... it's just a simple example of the various types of pieces and languages you might see (queues, persistent data, etc), and how to deal with them in Docker at a basic level.