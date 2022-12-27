/*

Packer file for lesson in Yandex Practicum (ycloud)
Uses two standard images (Ubuntu 20.04 LTS and Debian 11) and installs nging on them
After all it makes images in Yandex Compute Cloud
idk why it needs such ssh_username as shown, didn't found them on documentation 
*/


source "yandex" "ubuntu-nginx-2004" {
    //token = ....
    folder_id = "###FOLDER-ID###"
    source_image_family = "ubuntu-2004-lts"
    ssh_username = "ubuntu"
    //ssh_private_key_file = "~/.ssh/id_rsa"
    use_ipv4_nat = true
    image_description = "My custom Ubuntu 2004 image with nginx"
    image_family = "ubuntu-2004-lts"
    image_name = "my-ubuntu-2004-image"
    subnet_id = "e9bgun0ajtja3h3hiseq"
    disk_type = "network-ssd"
    zone = "ru-central1-a"

}


source "yandex" "debian-11" {
    //token = ....
    folder_id = "###FOLDER-ID###"
    source_image_family = "debian-11"
    ssh_username = "debian"
    //ssh_private_key_file = "~/.ssh/id_rsa"
    use_ipv4_nat = true
    image_description = "My custom debian-11 image with nginx"
    image_family = "debian-11"
    image_name = "my-debian-11-image"
    subnet_id = "e9bgun0ajtja3h3hiseq"
    disk_type = "network-ssd"
    zone = "ru-central1-a"

}

build {
    sources = ["source.yandex.ubuntu-nginx-2004", "source.yandex.debian-11"]

    provisioner "shell" {
        inline = [
            "sudo apt-get update -y",
            "sudo apt-get install -y nginx",
            "sudo systemctl enable nginx.service"
        ]
    }
}