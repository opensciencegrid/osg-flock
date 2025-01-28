
all: garbage_collection.x86_64 garbage_collection.aarch64

test: all
	./test.sh

clean:
	rm -rf test garbage_collection.x86_64 garbage_collection.aarch64

garbage_collection.x86_64: main.go
	GOARCH=amd64 go build -o garbage_collection.x86_64 main.go

garbage_collection.aarch64: main.go
	GOARCH=arm64 go build -o garbage_collection.aarch64 main.go


