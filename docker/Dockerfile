FROM public.ecr.aws/nginx/nginx
RUN apt-get update \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
RUN echo "This is v1!" > /usr/share/nginx/html/index.html