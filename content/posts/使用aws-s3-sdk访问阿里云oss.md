+++
title = '使用AWS S3 SDK访问阿里云oss'
date = 2024-09-01T10:14:00+08:00
tags = [ "Go" ]
draft = false
+++

- 目前业务上使用的是 `aws` 的 `s3` 服务，但是想兼容阿里云的 `oss`。根据`oss`的文档描述，`oss`支持使用 `aws` 的 `sdk` 进行访问，所以记录一下处理流程

### 访问AWS S3

```go
package main

import (
	"context"
	"log"
	"os"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

func NewS3Client() *s3.Client {
	accessKeyID := os.Getenv("ACCESS_KEY_ID")
	accessKeySecret := os.Getenv("ACCESS_KEY_SECRET")

	cfg, err := config.LoadDefaultConfig(
		context.TODO(),
		config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(accessKeyID, accessKeySecret, "")),
		config.WithEndpointResolverWithOptions(
			aws.EndpointResolverWithOptionsFunc(func(_, _ string, _ ...interface{}) (aws.Endpoint, error) {
				return aws.Endpoint{
					PartitionID:   "aws-cn",
					URL:           "https://s3.cn-northwest-1.amazonaws.com.cn",
					SigningRegion: "cn-northwest-1",
				}, nil
			}),
		),
	)
	if err != nil {
		log.Fatal(err)
	}
	return s3.NewFromConfig(cfg, func(o *s3.Options) {
		// 此选项可用于调试
		// o.ClientLogMode = aws.LogSigning | aws.LogRequest | aws.LogResponseWithBody
		o.UsePathStyle = true
	})
}

func main() {
	bucket := os.Getenv("S3_BUCKET")
	uploadKey := os.Getenv("S3_KEY")
	file, _ := os.Open("test.txt")

	client := NewS3Client()
	_, err := client.PutObject(context.Background(), &s3.PutObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(uploadKey),
		Body:   file,
	})
	if err != nil {
		log.Fatal(err)
	}
}
```

这是一个简单的 `s3` 文件上传，通过在 `PutObjectInput` 中指定`Bucket` 参数的形式。

### 使用 AWS SDK 访问阿里云 OSS

基于安全考虑，`OSS`仅支持`virtual hosted`访问方式。所以在`S3`迁移至`OSS`后，客户端应用需要进行相应设置。部分`S3`工具默认使用`Path style`，也需要进行相应配置，否则可能导致`OSS`报错，并禁止访问。

[Virtual hosted style](http://docs.aws.amazon.com/AmazonS3/latest/dev/VirtualHosting.html)是指将`Bucket`置于`Host Header`的访问方式。示例：

```bash
https://bucket-name.oss-cn-beijing.aliyuncs.com
```

基于阿里云的访问方式，我们需要对上面的代码进行一点点的修改：

```go
func NewS3Client(bucket string) *s3.Client {
	cfg, err := config.LoadDefaultConfig(
				// ...
				// 修改返回的 endpoint 为阿里云的服务
				return aws.Endpoint{
					PartitionID:   "oss",
					URL:           fmt.Sprintf("https://%s.oss-cn-beijing.aliyuncs.com", bucket),
					SigningRegion: "cn-beijing",
				}, nil
			}),
		),
	)
	// ...
	return s3.NewFromConfig(cfg, func(o *s3.Options) {
		o.UsePathStyle = true
	})
}

func main() {
	// ...
	client := NewS3Client(bucket)
	// ...
}
```

需要注意的是 `aws.Endpoint` 的 `URL` 字段的修改，一定要符合 `oss` 的访问约束。

而且在最后也需要设置`o.UsePathStyle = true`的选项。

其他的用法不变。

用于访问阿里云 `OSS` 的完整的代码如下：

```go
package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

func NewS3Client(bucket string) *s3.Client {
	accessKeyID := os.Getenv("ACCESS_KEY_ID")
	accessKeySecret := os.Getenv("ACCESS_KEY_SECRET")

	cfg, err := config.LoadDefaultConfig(
		context.TODO(),
		config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(accessKeyID, accessKeySecret, "")),
		config.WithEndpointResolverWithOptions(
			aws.EndpointResolverWithOptionsFunc(func(_, _ string, _ ...interface{}) (aws.Endpoint, error) {
				return aws.Endpoint{
					PartitionID:   "oss",
					URL:           fmt.Sprintf("https://%s.oss-cn-beijing.aliyuncs.com", bucket),
					SigningRegion: "cn-beijing",
				}, nil
			}),
		),
	)
	if err != nil {
		log.Fatal(err)
	}
	return s3.NewFromConfig(cfg, func(o *s3.Options) {
		o.UsePathStyle = true
	})
}

func main() {
	bucket := os.Getenv("S3_BUCKET")
	uploadKey := os.Getenv("S3_KEY")
	file, _ := os.Open("test.txt")

	client := NewS3Client(bucket)
	_, err := client.PutObject(context.Background(), &s3.PutObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(uploadKey),
		Body:   file,
	})
	if err != nil {
		log.Fatal(err)
	}
}

```

[阿里云 OSS 迁移文档](https://developer.alibaba.com/docs/doc.htm?treeId=620&articleId=116348&docType=1)
