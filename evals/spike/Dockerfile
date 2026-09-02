FROM node:22-bookworm
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      git python3 python3-pytest bash ca-certificates shellcheck \
    && rm -rf /var/lib/apt/lists/*
RUN npm install -g @anthropic-ai/claude-code@2.1.258 && claude --version
RUN git config --global user.name bdd-spike && git config --global user.email spike@bdd.local \
    && git config --global init.defaultBranch main
COPY . /opt/bdd
COPY evals/spike/phase1.sh /opt/phase1.sh
COPY evals/spike/probes.sh /opt/probes.sh
RUN chmod +x /opt/phase1.sh
WORKDIR /work
CMD ["bash"]
