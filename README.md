# AWS Flask Docker EC2

A small Flask web app packaged in a Docker container and deployed by hand to an Amazon EC2 instance. It serves a greeting at `/` and a JSON health check at `/health`, the kind of endpoint a load balancer uses to decide whether an app is alive.

This is Project 1 of my cloud engineering roadmap. Later projects move the same app into a custom VPC with RDS, rebuild the infrastructure in Terraform, and deploy it to ECS with a CI/CD pipeline.

## Architecture

```
Browser -> Internet -> Security group (80 open to all, 22 to my IP only)
        -> EC2 instance (Amazon Linux 2023, us-east-1)
        -> Docker: host port 80 -> container port 5000
        -> gunicorn -> Flask app
```

## Design decisions

- **gunicorn instead of Flask's built-in server.** Flask's server is for development only. gunicorn is a production web server for Python apps.
- **Dependencies installed before the code is copied.** Docker caches each build step and rebuilds everything after the first step that changes. Copying `requirements.txt` and installing it first means code edits reuse the cached dependency layer, so rebuilds take seconds.
- **`.dockerignore` excludes secrets and Git history.** Anything baked into an image layer can be extracted by whoever pulls the image, so `.git`, `.env` and `*.pem` never enter it.
- **The app binds to `0.0.0.0` inside the container.** Docker forwards published ports to the container's network interface, so an app bound to `127.0.0.1` is unreachable (see What broke).
- **SSH limited to my IP, HTTP open to everyone.** Only I need admin access, so port 22 allows a single `/32` address. Port 80 is open because it's a public website.
- **Cloned over HTTPS, with no SSH key on the server.** The repo is public, so HTTPS needs no credentials. Copying my private key to the server would expose my GitHub account if the server were compromised.

## How to run it

### Locally

```
docker build -t flask-app .
docker run -d --name flask-app -p 5000:5000 flask-app
curl http://localhost:5000
curl http://localhost:5000/health
```

### On EC2

Launch an Amazon Linux 2023 instance with a security group allowing port 80 from anywhere and port 22 from your IP only. Connect and install Docker and Git:

```
ssh -i ~/.ssh/flask-key.pem ec2-user@PUBLIC-IP
sudo dnf install -y docker git
sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user
```

Log out and back in so the group change applies, then build and run:

```
git clone https://github.com/brandonlsosa-dev/aws-flask-docker-ec2.git
cd aws-flask-docker-ec2
docker build -t flask-app .
docker run -d --name flask-app -p 80:5000 --restart unless-stopped flask-app
```

Open `http://PUBLIC-IP` in a browser. `--restart unless-stopped` brings the container back after a crash or reboot.

### Evidence

The instance has been terminated. Output captured while it was running: [run-output.txt](docs/run-output.txt)

![App in the browser](docs/browser.png)

![Security group inbound rules](docs/security-group.png)

## Cost and teardown

Ran on a t3.micro instance in us-east-1 for about 4 hours. While running, it bills for instance hours and the public IPv4 address, about $0.015 per hour combined. I set a $10 monthly AWS Budget alert before starting and terminated the instance after testing, which also deleted its root volume. The key pair and security group were kept because they cost nothing. Total cost: PENDING.

## What broke and what I learned

**An app can show "Up" and still be unreachable.** As an experiment I changed gunicorn to bind to `127.0.0.1:5000`. `docker ps` showed the container as `Up` and the logs had no errors, but `curl` failed with `Connection reset by peer`. The log line `Listening at: http://127.0.0.1:5000` was the clue. Inside a container, 127.0.0.1 is the container itself, and Docker forwards published ports to the container's network interface, not its loopback. Binding to `0.0.0.0` fixed it. When a container looks healthy but can't be reached, I now check the bind address first.

**Refused and timed out mean different things.** Stopping the container made `curl` fail in about 35 ms: the packets reached the server, nothing was listening, and it rejected them immediately. Removing the security group's HTTP rule made `curl` hang for the full 5-second timeout: the packets were dropped and nothing replied. A fast failure points at the app or its port. A slow one points at the firewall or network path.

**A test only counts if the change took effect.** My first attempt at the bind experiment seemed to pass, because the build command was missing its build context (`.`) and never rebuilt the image. `docker ps` and the logs still showed `0.0.0.0`. I now check that evidence before trusting a result.

**GitHub blocked a push that exposed my private email.** My Git config in WSL used my real address, so the push was rejected with GH007. I set the noreply address and amended the unpushed commit with `--reset-author`. Rewriting history was safe only because the commit hadn't been pushed yet.

**A one-character typo reached GitHub because I didn't build first.** Uppercasing `run` to `RUN` with `sed` dropped a space and produced `RUNpip`, which I pushed before noticing. I fixed it with a new commit instead of rewriting pushed history, and I now run `docker build` before every Dockerfile commit.
