import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
	const { deployments, getNamedAccounts } = hre;
	const { deploy, get } = deployments;

	const { deployer } = await getNamedAccounts();

    const launchpadDeployer = await get('LaunchpadDeployer');

    // 5% fee
    await deploy('LaunchpadFactory', {
        from: deployer,
        log: true,
        args: [deployer, 500, launchpadDeployer.address]
    });

};
export default func;
func.tags = ['launchpad_factory'];
func.dependencies = ['launchpad_deployer'];