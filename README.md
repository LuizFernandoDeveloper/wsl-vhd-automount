# wsl-vhd-automount

Automount inteligente para VHDX no WSL 2: detecta o disco dinamicamente, monta no login e evita links quebrados apos reboot, troca de drive ou `wsl --shutdown`.

Esta automacao anexa um VHDX ext4 no Windows e monta esse disco no WSL 2 sem depender de um `\\.\PHYSICALDRIVE2` fixo.

## O problema que isto resolve

O `.bat` antigo montava o VHDX e chamava:

```bat
wsl --mount \\.\PHYSICALDRIVE2
```

Esse numero pode mudar a cada boot, depois de plugar/remover discos, ou depois de operacoes como `wsl --shutdown`. Quando muda, o atalho continua apontando para o `PhysicalDrive` errado.

Agora o fluxo e:

1. Anexar o VHDX com `Mount-VHD`.
2. Perguntar ao Windows qual `PhysicalDrive` foi atribuido naquele momento.
3. Chamar `wsl --mount` usando o disco detectado dinamicamente.
4. Registrar logs para diagnostico.

Isso segue a tecnica documentada pela Microsoft para VHD em WSL: primeiro `Mount-VHD`, depois `Get-Disk`, depois `wsl --mount`.

Referencia:

- [Mount a Linux disk in WSL 2](https://learn.microsoft.com/en-us/windows/wsl/wsl2-mount-disk)
- [Basic commands for WSL](https://learn.microsoft.com/en-us/windows/wsl/basic-commands)

## Estrutura

```text
config/
  wsl-vhd.config.ps1
scripts/
  Mount-WslVhd.ps1
  Unmount-WslVhd.ps1
  Show-Status.ps1
  Install-StartupTask.ps1
  Remove-StartupTask.ps1
  WslVhd.Common.ps1
media_removivel_init.bat
```

## Configuracao

Edite `config/wsl-vhd.config.ps1` se precisar trocar caminho, nome do mount ou distro:

```powershell
$WslVhdConfig = @{
    VhdPath = '..\WSL_Drives.vhdx'
    MountName = 'media-removivel'
    FileSystem = 'ext4'
    Partition = $null
    DistroName = ''
    StartDistro = $false
}
```

Com a configuracao atual, o disco fica em:

```text
/mnt/wsl/media-removivel
```

No Explorer, use um caminho desse tipo:

```text
\\wsl.localhost\<NomeDaDistro>\mnt\wsl\media-removivel
```

Dentro da distro, se quiser manter um link estavel:

```sh
ln -sfn /mnt/wsl/media-removivel ~/media-removivel
```

## Uso manual

Abra PowerShell como Administrador e rode:

```powershell
.\scripts\Mount-WslVhd.ps1
```

Ou use o `.bat` antigo, que agora virou wrapper:

```bat
.\media_removivel_init.bat
```

Para ver o estado:

```powershell
.\scripts\Show-Status.ps1
```

Para desmontar:

```powershell
.\scripts\Unmount-WslVhd.ps1
```

Se o WSL travou segurando o disco, use:

```powershell
.\scripts\Unmount-WslVhd.ps1 -ShutdownWsl
```

## Automatizar no login

Use uma Tarefa Agendada com privilegio elevado. Isso e mais confiavel do que colocar um atalho `.bat` na pasta Inicializar.

Abra PowerShell como Administrador:

```powershell
.\scripts\Install-StartupTask.ps1
```

Para instalar e ja testar:

```powershell
.\scripts\Install-StartupTask.ps1 -RunNow
```

Para remover:

```powershell
.\scripts\Remove-StartupTask.ps1
```

O instalador cria um bootstrap em:

```text
%LOCALAPPDATA%\WslVhdAutomount\Start-WslVhdAutomount.ps1
```

Esse bootstrap procura a pasta do projeto em todos os drives. Assim, se a midia removivel mudar de letra, a Tarefa Agendada ainda tem uma chance boa de encontrar o script.

## Logs

Logs do mount:

```text
.\logs\wsl-vhd-automount.log
```

Logs do bootstrap da Tarefa Agendada:

```text
%LOCALAPPDATA%\WslVhdAutomount\bootstrap.log
```

## Notas importantes

- `Mount-VHD` e `wsl --mount` exigem Administrador.
- O VHDX nao deve entrar no repositorio. O `.gitignore` ja ignora `*.vhd` e `*.vhdx`.
- Evite rodar `wsl --shutdown` enquanto estiver gravando dados nesse disco.
- Se precisar recuperar uma montagem quebrada, primeiro tente `.\scripts\Unmount-WslVhd.ps1 -ShutdownWsl` e depois `.\scripts\Mount-WslVhd.ps1`.
