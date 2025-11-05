VERSION=v1
<<<<<<< HEAD
DOCKERUSER=YOUR_DOCKER_USERNAME_HERE
=======
DOCKERUSER=rash4560
>>>>>>> 4625728 (Updated code)

build:
	docker build -f Dockerfile -t demucs-worker .
push:
	docker tag demucs-worker $(DOCKERUSER)/demucs-worker:$(VERSION)
	docker push $(DOCKERUSER)/demucs-worker:$(VERSION)
	docker tag demucs-worker $(DOCKERUSER)/demucs-worker:latest
	docker push $(DOCKERUSER)/demucs-worker:latest
