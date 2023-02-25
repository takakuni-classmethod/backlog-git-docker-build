variable "system" {
  type    = string
  default = "backlog"
}

variable "env" {
  type    = string
  default = "cicd"
}

variable "cidr" {
  default = {
    vpc       = "192.168.0.0/16"
    public_a  = "192.168.0.0/24"
    public_c  = "192.168.1.0/24"
    private_a = "192.168.2.0/24"
    private_c = "192.168.3.0/24"
  }
}

variable "backlog" {
  default = {
    space_id        = "" # htts://sample.backlog.jp の sample の部分
    domain_name     = "" # backlog.jp または backlog.com
    project_key     = "" # https://backlog.com/ja/enterprise-help/userguide/userguide353/
    repository_name = "" # Backlog Git のレポジトリ名
    webhook_ip = [
      "54.248.107.22/32",
      "54.248.105.89/32",
      "54.238.168.195/32",
      "52.192.66.90/32",
      "54.65.251.183/32",
      "54.250.148.49/32",
      "35.166.55.243/32",
      "50.112.242.159/32",
      "52.199.112.83/32",
      "35.73.201.244/32",
      "35.72.166.154/32",
      "35.73.143.41/32",
      "35.74.201.20/32",
      "52.198.115.185/32",
      "35.165.230.177/32",
      "18.236.6.123/32",
    ] # https://support-ja.backlog.com/hc/ja/articles/360035645534-Webhook-%E9%80%81%E4%BF%A1%E3%82%B5%E3%83%BC%E3%83%90%E3%83%BC%E3%81%AE-IP-%E3%82%A2%E3%83%89%E3%83%AC%E3%82%B9%E3%82%92%E6%95%99%E3%81%88%E3%81%A6%E3%81%8F%E3%81%A0%E3%81%95%E3%81%84
  }
}