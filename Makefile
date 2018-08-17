VERSION=0.45
BINARY_NAME=statup
GOPATH:=$(GOPATH)
GOCMD=go
GOBUILD=$(GOCMD) build
GOTEST=$(GOCMD) test
GOGET=$(GOCMD) get
GOINSTALL=$(GOCMD) install
XGO=GOPATH=$(GOPATH) $(GOPATH)/bin/xgo -go 1.10.x --dest=build
BUILDVERSION=-ldflags "-X main.VERSION=$(VERSION) -X main.COMMIT=$(TRAVIS_COMMIT)"
RICE=$(GOPATH)/bin/rice
PATH:=/usr/local/bin:$(GOPATH)/bin:$(PATH)
PUBLISH_BODY='{ "request": { "branch": "master", "config": { "env": { "VERSION": "$(VERSION)", "COMMIT": "$(TRAVIS_COMMIT)" } } } }'
TRAVIS_BUILD_CMD='{ "os": [ "linux" ], "language": "go", "go": [ "1.10.x" ], "go_import_path": "github.com/hunterlong/statup", "install": true, "sudo": "required", "services": [ "docker" ], "env": { "global": [ "DB_HOST=localhost", "DB_USER=travis", "DB_PASS=", "DB_DATABASE=test", "GO_ENV=test", "STATUP_DIR=$GOPATH/src/github.com/hunterlong/statup" ] }, "matrix": { "allow_failures": [ { "go": "master" } ], "fast_finish": true }, "before_deploy": [ "git config --local user.name \"hunterlong\"", "git config --local user.email \"info@socialeck.com\"", "make tag" ], "deploy": [ { "provider": "releases", "api_key": "$GH_TOKEN", "file": [ "build/statup-osx-x64.tar.gz", "build/statup-osx-x32.tar.gz", "build/statup-linux-x64.tar.gz", "build/statup-linux-x32.tar.gz", "build/statup-linux-arm64.tar.gz", "build/statup-linux-arm7.tar.gz", "build/statup-linux-alpine.tar.gz", "build/statup-windows-x64.zip" ], "skip_cleanup": true } ], "notifications": { "email": false }, "before_script": [], "script": [ "if [[ \"$TRAVIS_BRANCH\" == \"master\" ]]; then travis_wait 30 docker pull karalabe/xgo-latest; fi", "if [[ \"$TRAVIS_BRANCH\" == \"master\" ]]; then make release; fi" ], "after_success": [], "after_deploy": [ "if [[ \"$TRAVIS_BRANCH\" == \"master\" ]]; then make publish-dev; fi" ] }'
TEST_DIR=$(GOPATH)/src/github.com/hunterlong/statup

all: dev-deps compile install test-all

release: dev-deps build-all compress

test-all: dev-deps test cypress-test

travis-test: dev-deps cypress-install test docker-test cypress-test coverage

build: compile
	$(GOBUILD) $(BUILDVERSION) -o $(BINARY_NAME) -v ./cmd

install: clean build
	mv $(BINARY_NAME) $(GOPATH)/bin/$(BINARY_NAME)
	$(GOPATH)/bin/$(BINARY_NAME) version

run: build
	./$(BINARY_NAME) --ip 0.0.0.0 --port 8080

compile:
	cd source && $(GOPATH)/bin/rice embed-go
	sass source/scss/base.scss source/css/base.css

test: clean compile install
	STATUP_DIR=$(TEST_DIR) go test -v -p=1 $(BUILDVERSION) -coverprofile=coverage.out ./...
	gocov convert coverage.out > coverage.json

coverage:
	$(GOPATH)/bin/goveralls -coverprofile=coverage.out -service=travis -repotoken $(COVERALLS)

docs:
	godoc2md github.com/hunterlong/statup > servers/docs/README.md
	gocov-html coverage.json > servers/docs/COVERAGE.html
	revive -formatter stylish > servers/docs/LINT.md

build-all: clean compile
	mkdir build
	$(XGO) $(BUILDVERSION) --targets=darwin/amd64 ./cmd
	$(XGO) $(BUILDVERSION) --targets=darwin/386 ./cmd
	$(XGO) $(BUILDVERSION) --targets=linux/amd64 ./cmd
	$(XGO) $(BUILDVERSION) --targets=linux/386 ./cmd
	$(XGO) $(BUILDVERSION) --targets=windows-6.0/amd64 ./cmd
	$(XGO) $(BUILDVERSION) --targets=linux/arm-7 ./cmd
	$(XGO) $(BUILDVERSION) --targets=linux/arm64 ./cmd
	$(XGO) --targets=linux/amd64 -ldflags="-X main.VERSION=$(VERSION) -X main.COMMIT=$(TRAVIS_COMMIT) -linkmode external -extldflags -static" -out alpine ./cmd

build-alpine: clean compile
	mkdir build
	$(XGO) --targets=linux/amd64 -ldflags="-X main.VERSION=$(VERSION) -X main.COMMIT=$(TRAVIS_COMMIT) -linkmode external -extldflags -static" -out alpine ./cmd

docker:
	docker build -t hunterlong/statup:latest .

docker-run: docker
	docker run -t -p 8080:8080 hunterlong/statup:latest

docker-dev:
	docker build -t hunterlong/statup:dev -f ./.dev/Dockerfile .

docker-run-dev: clean docker-dev
	docker run -t -p 8080:8080 hunterlong/statup:dev

docker-test: docker-dev
	docker run -t -p 8080:8080 --entrypoint="STATUP_DIR=`pwd` GO_ENV=test go test -v -p=1 $(BUILDVERSION)  ./..." hunterlong/statup:dev

databases:
	docker run --name statup_postgres -p 5432:5432 -e POSTGRES_PASSWORD=password123 -e POSTGRES_USER=root -e POSTGRES_DB=root -d postgres
	docker run --name statup_mysql -p 3306:3306 -e MYSQL_ROOT_PASSWORD=password123 -e MYSQL_DATABASE=root -d mysql
	sleep 30

dep:
	dep ensure

dev-deps:
	$(GOGET) github.com/stretchr/testify/assert
	$(GOGET) golang.org/x/tools/cmd/cover
	$(GOGET) github.com/mattn/goveralls
	$(GOINSTALL) github.com/mattn/goveralls
	$(GOGET) github.com/rendon/testcli
	$(GOGET) github.com/karalabe/xgo
	$(GOGET) github.com/GeertJohan/go.rice
	$(GOGET) github.com/GeertJohan/go.rice/rice
	$(GOINSTALL) github.com/GeertJohan/go.rice/rice
	$(GOCMD) get github.com/davecheney/godoc2md
	$(GOCMD) install github.com/davecheney/godoc2md
	$(GOCMD) get github.com/axw/gocov/gocov
	$(GOCMD) get gopkg.in/matm/v1/gocov-html
	$(GOCMD) install gopkg.in/matm/v1/gocov-html
	$(GOCMD) get github.com/mgechev/revive

clean:
	rm -rf ./{logs,assets,plugins,statup.db,config.yml,.sass-cache,config.yml,statup,build}
	rm -rf cmd/{logs,assets,plugins,statup.db,config.yml,.sass-cache}
	rm -rf core/{logs,assets,plugins,statup.db,config.yml,.sass-cache}
	rm -rf handlers/{logs,assets,plugins,statup.db,config.yml,.sass-cache}
	rm -rf notifiers/{logs,assets,plugins,statup.db,config.yml,.sass-cache}
	rm -rf source/{logs,assets,plugins,statup.db,config.yml,.sass-cache}
	rm -rf types/{logs,assets,plugins,statup.db,config.yml,.sass-cache}
	rm -rf utils/{logs,assets,plugins,statup.db,config.yml,.sass-cache}
	rm -rf .dev/test/cypress/videos
	rm -rf .sass-cache
	rm -f coverage.out
	rm -f coverage.json

tag:
	git tag "v$(VERSION)" --force

compress:
	cd build && mv alpine-linux-amd64 $(BINARY_NAME)
	cd build && tar -czvf $(BINARY_NAME)-linux-alpine.tar.gz $(BINARY_NAME) && rm -f $(BINARY_NAME)
	cd build && mv cmd-darwin-10.6-amd64 $(BINARY_NAME)
	cd build && tar -czvf $(BINARY_NAME)-osx-x64.tar.gz $(BINARY_NAME) && rm -f $(BINARY_NAME)
	cd build && mv cmd-darwin-10.6-386 $(BINARY_NAME)
	cd build && tar -czvf $(BINARY_NAME)-osx-x32.tar.gz $(BINARY_NAME) && rm -f $(BINARY_NAME)
	cd build && mv cmd-linux-amd64 $(BINARY_NAME)
	cd build && tar -czvf $(BINARY_NAME)-linux-x64.tar.gz $(BINARY_NAME) && rm -f $(BINARY_NAME)
	cd build && mv cmd-linux-386 $(BINARY_NAME)
	cd build && tar -czvf $(BINARY_NAME)-linux-x32.tar.gz $(BINARY_NAME) && rm -f $(BINARY_NAME)
	cd build && mv cmd-windows-6.0-amd64.exe $(BINARY_NAME).exe
	cd build && zip $(BINARY_NAME)-windows-x64.zip $(BINARY_NAME).exe  && rm -f $(BINARY_NAME).exe
	cd build && mv cmd-linux-arm-7 $(BINARY_NAME)
	cd build && tar -czvf $(BINARY_NAME)-linux-arm7.tar.gz $(BINARY_NAME) && rm -f $(BINARY_NAME)
	cd build && mv cmd-linux-arm64 $(BINARY_NAME)
	cd build && tar -czvf $(BINARY_NAME)-linux-arm64.tar.gz $(BINARY_NAME) && rm -f $(BINARY_NAME)

publish-dev:
	curl -H "Content-Type: application/json" --data '{"docker_tag": "dev"}' -X POST $(DOCKER)

publish-latest:
	curl -H "Content-Type: application/json" --data '{"docker_tag": "latest"}' -X POST $(DOCKER)

publish-homebrew:
	curl -s -X POST -H "Content-Type: application/json" -H "Accept: application/json" -H "Travis-API-Version: 3" -H "Authorization: token $(TRAVIS_API)" -d $(PUBLISH_BODY) https://api.travis-ci.com/repo/hunterlong%2Fhomebrew-statup/requests

cypress-install:
	cd .dev/test && npm install

cypress-test: clean cypress-install
	cd .dev/test && npm test

travis-build:
	curl -s -X POST -H "Content-Type: application/json" -H "Accept: application/json" -H "Travis-API-Version: 3" -H "Authorization: token $(TRAVIS_API)" -d $(TRAVIS_BUILD_CMD) https://api.travis-ci.com/repo/hunterlong%2Fstatup/requests

.PHONY: build build-all build-alpine test-all test