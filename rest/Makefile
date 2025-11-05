VERSION=v1
<<<<<<< HEAD
DOCKERUSER=YOUR_DOCKER_USERNAME_HERE
=======
DOCKERUSER=rash4560
>>>>>>> 4625728 (Updated code)

build:
	docker build -f Dockerfile-rest -t demucs-rest .

push:
	docker tag demucs-rest $(DOCKERUSER)/demucs-rest:$(VERSION)
	docker push $(DOCKERUSER)/demucs-rest:$(VERSION)
	docker tag demucs-rest $(DOCKERUSER)/demucs-rest:latest
	docker push $(DOCKERUSER)/demucs-rest:latest
