# zzhaolei.github.io

## 克隆项目
```
git clone https://github.com/zzhaolei/zzhaolei.github.io.git
git submodule update --recursive --remote

# 如果目录不存在则创建
ls content/posts || make -p content/posts
```

## 更新文章
```
hugo new content content/posts/my-first-post.md
```

## 本地预览
```
hugo serve -D
```
